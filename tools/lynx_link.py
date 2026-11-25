#!/usr/bin/env python3
"""Inspect and load owner-supplied images through SRVL's Tang UART.

The bench protocol is ASCII so payloads cannot contain the debugger's binary
console escape. No device is selected, programmed or contacted by inspection.
"""

import argparse
import binascii
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys
import time


RAW_SIZES = {65536, 131072, 262144, 524288}
STATUS_BITS = {"memory_ready": 0, "bios_valid": 1, "running": 2,
               "image_valid": 3, "loading": 4, "protocol_error": 5,
               "frame_valid": 8, "overflow": 9, "underflow": 10,
               "video_protocol_fault": 11,
               "memory_protocol_fault": 12, "audio_ready": 13, "audio_underrun": 14}


@dataclass(frozen=True)
class Image:
    kind: str
    original: bytes
    payload: bytes

    def summary(self):
        return {"kind": self.kind, "input_bytes": len(self.original),
                "wire_bytes": len(self.payload),
                "padded_bytes": len(self.payload)-len(self.original),
                "input_sha256": hashlib.sha256(self.original).hexdigest(),
                "wire_sha256": hashlib.sha256(self.payload).hexdigest()}


def prepare_image(data):
    """Validate against the pinned core's supported single-bank/header behavior."""
    if data.startswith(b"LYNX"):
        if len(data) < 64:
            raise ValueError("LNX header is shorter than 64 bytes")
        bank0 = int.from_bytes(data[4:6], "little")
        bank1 = int.from_bytes(data[6:8], "little")
        version = int.from_bytes(data[8:10], "little")
        if version != 1 or bank1 != 0 or bank0 not in {0x100, 0x200, 0x400, 0x800}:
            raise ValueError("core requires LNX v1, a supported bank-0 page size, and no second bank")
        if len(data) != 64 + bank0*256:
            raise ValueError("LNX payload length does not match bank-0 geometry")
        return Image("LNX", data, data)  # Preserve the header; the core adds 64.
    if len(data) >= 10 and data[6:10] == b"BS93":
        entry = int.from_bytes(data[2:4], "big")
        size = int.from_bytes(data[4:6], "big")
        if entry == 0 or size == 0 or len(data) != size+10:
            raise ValueError("BS93 entry/length is invalid or the image is truncated")
        payload = bytearray(data)
        if size & 1:
            # Upstream consumes complete words and decrements its byte count for
            # both bytes. Add a trailing NOP and adjust the container's count.
            size += 1
            if size > 0xffff:
                raise ValueError("padded BS93 payload exceeds its 16-bit length")
            payload[4:6] = size.to_bytes(2, "big")
            payload.append(0xea)
        if entry+size > 65536:
            raise ValueError("BS93 payload would wrap the 64 KiB RAM address space")
        return Image("BS93", data, bytes(payload))
    if len(data) not in RAW_SIZES:
        raise ValueError("raw cartridge size must be 64, 128, 256 or 512 KiB; unsupported/invalid header")
    return Image("raw", data, data)


def request(opcode, address=0, data=0):
    if opcode not in {"Q", "L", "B", "W", "C", "K", "R"}:
        raise ValueError("unknown opcode")
    if not 0 <= address <= 0xffffff or not 0 <= data <= 0xffff:
        raise ValueError("request field out of range")
    prefix = f"{opcode}{address:06X}{data:04X}".encode("ascii")
    return prefix + f"{binascii.crc_hqx(prefix, 0xffff):04X}\n".encode("ascii")


def response(line):
    if not re.fullmatch(rb"[KE][0-9A-Fa-f]{12}\n", line):
        raise ValueError("invalid reply framing")
    if binascii.crc_hqx(line[:9], 0xffff) != int(line[9:13], 16):
        raise ValueError("reply CRC mismatch")
    status = int(line[1:9], 16)
    if status >> 16 != 0x4c59:
        raise ValueError("device did not return the SRVL Lynx signature")
    return line[:1] == b"K", status


def decode_status(status):
    return {"value": f"0x{status:08X}", **{name: bool(status & (1 << bit)) for name, bit in STATUS_BITS.items()}}


class Link:
    def __init__(self, serial, timeout=1.0):
        self.serial, self.timeout = serial, timeout

    def transact(self, opcode, address=0, data=0):
        packet = request(opcode, address, data)
        # Write one complete request; no pipelining. An uncertain ACK is not an
        # excuse to issue a different command or silently restart an upload.
        if self.serial.write(packet) != len(packet):
            raise OSError("partial serial write; reset/resynchronize before another request")
        self.serial.flush()
        deadline, line = time.monotonic()+self.timeout, bytearray()
        while time.monotonic() < deadline:
            byte = self.serial.read(1)
            if not byte:
                continue
            line.extend(byte)
            if len(line) > 64:
                raise ValueError("unexpected debugger/serial output; check UART bridge mode and clocks")
            if byte == b"\n":
                accepted, status = response(bytes(line))
                if not accepted:
                    raise RuntimeError(f"device rejected {opcode} at 0x{address:06X}: {decode_status(status)}")
                return status
        raise TimeoutError(f"no validated ACK for {opcode}; command outcome is uncertain; no automatic relaunch")


def load(link, image, bios=None, progress=None):
    if bios is not None and len(bios) != 512:
        raise ValueError("the original BIOS upload must be exactly 512 bytes")
    status = link.transact("Q")
    if not status & 1:
        raise RuntimeError("SDRAM is not initialized")
    if image.kind != "BS93" and bios is None and not status & 2:
        raise ValueError("a complete 512-byte BIOS is required before this cartridge can launch")
    link.transact("L")
    if bios is not None:
        for address, value in enumerate(bios):
            link.transact("B", address, value)
    for address in range(0, len(image.payload), 2):
        word = int.from_bytes(image.payload[address:address+2], "little")
        link.transact("W", address, word)
        if progress and (address % 4096 == 0 or address+2 == len(image.payload)):
            progress(address+2, len(image.payload))
    status = link.transact("C", len(image.payload)-1)
    if status & 0x0c != 0x0c:
        raise RuntimeError("commit did not report a running valid image")
    return status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    inspect = sub.add_parser("inspect", help="validate/hash an image without a serial device")
    inspect.add_argument("image", type=Path)
    for name in ["query", "load", "buttons", "stop"]:
        command = sub.add_parser(name)
        command.add_argument("--port", required=True, help="explicit UART device path; never auto-selected")
        command.add_argument("--timeout", type=float, default=1.0)
        if name == "load":
            command.add_argument("image", type=Path)
            command.add_argument("--bios", type=Path)
        if name == "buttons":
            command.add_argument("mask", type=lambda value: int(value, 0), help="9-bit held-button mask; zero releases all buttons")
    args = parser.parse_args(argv)
    try:
        image = prepare_image(args.image.read_bytes()) if args.command in {"inspect", "load"} else None
        if args.command == "inspect":
            print(json.dumps(image.summary(), indent=2)); return 0
        bios = args.bios.read_bytes() if args.command == "load" and args.bios else None
        if bios is not None and len(bios) != 512:
            raise ValueError("BIOS must be exactly 512 bytes")
        if args.command == "buttons" and not 0 <= args.mask <= 0x1ff:
            raise ValueError("button mask must fit nine bits")
        if args.timeout <= 0:
            raise ValueError("timeout must be positive")
        import serial  # The Nix app supplies pyserial; inspection is stdlib-only.
        with serial.Serial(args.port, baudrate=460800, timeout=0.05, write_timeout=args.timeout, exclusive=True) as port:
            link = Link(port, args.timeout)
            if args.command == "load":
                print(json.dumps(image.summary(), indent=2))
                status = load(link, image, bios,
                              lambda done, total: print(f"\rUploaded {done}/{total} bytes", end="", file=sys.stderr, flush=True))
                print(file=sys.stderr)
            else:
                status = link.transact({"query": "Q", "buttons": "K", "stop": "R"}[args.command],
                                       data=args.mask if args.command == "buttons" else 0)
            print(json.dumps(decode_status(status), indent=2))
        return 0
    except (ValueError, OSError, RuntimeError) as error:
        print(f"lynx-link: {error}", file=sys.stderr); return 1


if __name__ == "__main__":
    raise SystemExit(main())
