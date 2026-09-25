"""Original synthetic MMDB builder for local backend tests; no provider data."""

import struct


def text(value):
    encoded = value.encode()
    assert len(encoded) < 29
    return bytes([0x40 | len(encoded)]) + encoded


def mapping(items):
    return bytes([0xE0 | len(items)]) + b"".join(
        text(key) + value for key, value in items
    )


def database():
    # One-node IPv6 database; all addresses deliberately map to the test country.
    def small(value):
        return b"\xa2" + struct.pack(">H", value)

    return (
        bytes([0, 0, 17, 0, 0, 17])
        + bytes(16)
        + mapping([("country", mapping([("iso_code", text("IT"))]))])
        + b"\xab\xcd\xefMaxMind.com"
        + mapping(
            [
                ("binary_format_major_version", small(2)),
                ("binary_format_minor_version", small(0)),
                ("build_epoch", b"\x08\x02" + struct.pack(">Q", 1704067200)),
                ("database_type", text("Outbound-Synthetic-Country")),
                ("description", mapping([("en", text("Synthetic test data"))])),
                ("ip_version", small(6)),
                ("languages", b"\x01\x04" + text("en")),
                ("node_count", b"\xc1\x01"),
                ("record_size", small(24)),
            ]
        )
    )
