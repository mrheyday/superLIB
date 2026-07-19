#!/usr/bin/env python3
"""
ORCH-H codec (stub)
Canonical word <-> byte encoder / decoder
"""

WORD_TO_BYTE = {
    "bela": 0x10,
    "bele": 0x11,
    "beli": 0x12,
    "belo": 0x13,
    "belu": 0x14,
    "bera": 0x1F,
}

BYTE_TO_WORD = {v: k for k, v in WORD_TO_BYTE.items()}

def encode(words):
    return bytes(WORD_TO_BYTE[w] for w in words)

def decode(blob):
    return [BYTE_TO_WORD[b] for b in blob]
