"""Host format/safety checks plus replies captured from the actual simulated RTL."""
import binascii
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import lynx_link as link


FIXTURES = Path(sys.argv.pop(1))


class Wire:
    def __init__(self, reply):
        self.reply, self.written = bytearray(reply), bytearray()
    def write(self, data):
        self.written.extend(data)
        return len(data)
    def read(self, size):
        if not self.reply:
            return b""
        result = bytes(self.reply[:size])
        del self.reply[:size]
        return result
    def flush(self):
        pass


class HostChecks(unittest.TestCase):
    def test_presentation_status_wire_bits(self):
        base = 0x4c590001
        for bit, name in [(8,"frame_valid"),(9,"overflow"),(10,"underflow"),
                          (11,"video_protocol_fault"),(12,"memory_protocol_fault"),
                          (13,"audio_ready"),(14,"audio_underrun")]:
            flags = link.decode_status(base | (1 << bit))
            self.assertTrue(flags["memory_ready"])
            self.assertTrue(flags[name])
            for other in ["frame_valid","overflow","underflow","video_protocol_fault","memory_protocol_fault","audio_ready","audio_underrun"]:
                if other != name:
                    self.assertFalse(flags[other])

    def test_real_rtl_replies(self):
        rows = FIXTURES.read_text().splitlines()
        self.assertGreaterEqual(len(rows), 25)
        for row in rows:
            request_hex, reply_hex = row.split("\t")
            request, reply = bytes.fromhex(request_hex), bytes.fromhex(reply_hex)
            accepted, status = link.response(reply)
            self.assertEqual(accepted, reply[:1] == b"K")
            self.assertEqual(status >> 16, 0x4c59)
            if accepted and len(request) == 16:
                self.assertEqual(link.request(chr(request[0]), int(request[1:7],16), int(request[7:11],16)), request)
            corrupted = bytearray(reply)
            corrupted[4] = ord("1") if corrupted[4] != ord("1") else ord("2")
            with self.assertRaisesRegex(ValueError, "CRC"):
                link.response(bytes(corrupted))

    def test_link_against_captured_query(self):
        first = FIXTURES.read_text().splitlines()[0].split("\t")
        request, reply = map(bytes.fromhex, first)
        serial = Wire(reply)
        status = link.Link(serial).transact("Q")
        self.assertEqual(bytes(serial.written), request)
        self.assertEqual(status >> 16, 0x4c59)

    def test_uncertain_ack_does_not_retry_or_launch(self):
        serial = Wire(b"")
        with patch("lynx_link.time.monotonic", side_effect=[0,0,2]):
            with self.assertRaises(TimeoutError):
                link.Link(serial).transact("W", 0, 0x0318)
        self.assertEqual(bytes(serial.written), link.request("W",0,0x0318))

    def test_payload_is_ascii_and_never_debugger_escape(self):
        for value in range(65536):
            packet = link.request("W", 0x123456, value)
            self.assertEqual(len(packet),16)
            self.assertNotIn(0x18,packet)
            self.assertNotIn(0x03,packet)
        self.assertEqual(binascii.crc_hqx(b"123456789",0xffff),0x29b1)

    def test_bs93_odd_padding_changes_length_and_keeps_input(self):
        original = b"\x80\x08\x02\x00\x00\x03BS93\xa9\x18\x03"
        image = link.prepare_image(original)
        self.assertEqual(image.kind,"BS93")
        self.assertEqual(image.original,original)
        self.assertEqual(image.payload[4:6],b"\x00\x04")
        self.assertEqual(image.payload[10:],b"\xa9\x18\x03\xea")
        self.assertEqual(image.summary()["padded_bytes"],1)
        for data in [original[:-1],original[:2]+b"\xff\xff"+original[4:],original[:2]+b"\0\0"+original[4:]]:
            with self.assertRaises(ValueError):
                link.prepare_image(data)

    def test_lnx_header_retained_and_second_bank_rejected(self):
        data = bytearray(64+65536)
        data[:10] = b"LYNX\x00\x01\0\0\x01\0"
        self.assertEqual(link.prepare_image(bytes(data)).payload, bytes(data))
        data[6] = 1
        with self.assertRaisesRegex(ValueError,"second bank"):
            link.prepare_image(bytes(data))

    def test_raw_size_limits(self):
        for size in link.RAW_SIZES:
            image = link.prepare_image(bytes(size))
            self.assertEqual(image.kind,"raw")
        for size in [0,10,65535,65537,1048576]:
            with self.assertRaises(ValueError):
                link.prepare_image(bytes(size))

    def test_bad_bios_and_missing_bios_do_not_begin_load(self):
        class RecordingLink:
            def __init__(self): self.calls=[]
            def transact(self,op,*args):
                self.calls.append(op)
                return 0x4c590001
        target = RecordingLink()
        image = link.prepare_image(bytes(65536))
        with self.assertRaises(ValueError):
            link.load(target,image,b"bad")
        self.assertEqual(target.calls,[])
        with self.assertRaisesRegex(ValueError,"BIOS"):
            link.load(target,image)
        self.assertEqual(target.calls,["Q"])


if __name__ == "__main__":
    unittest.main()
