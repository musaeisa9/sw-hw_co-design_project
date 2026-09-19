import mmap
import struct
import os

class HuffmanAcceleratorDriver:
    def __init__(self):
        # Physical base address of the RTL accelerator (example: 0x40000000)
        self.HW_BASE = 0x40000000
        self.mem_fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        self.mm = mmap.mmap(self.mem_fd, 0x10000, mmap.MAP_SHARED, 
                            mmap.PROT_READ | mmap.PROT_WRITE, offset=self.HW_BASE)

    def write_reg(self, offset, value):
        self.mm[offset:offset+4] = struct.pack('<I', value)

    def configure_hardware(self, tables, selectors_list):
        # 1. Write the Selectors List to HW memory
        for i, sel in enumerate(selectors_list):
            self.write_reg(0x0000 + (i * 4), sel)

        # 2. Write the Canonical Tables
        for table_idx, t in enumerate(tables):
            TABLE_BASE = 0x1000 + (table_idx * 0x1000)
            
            min_code = [0xFFFFFFFF] * 21
            max_code = [0] * 21
            base_idx = [0] * 21
            symbols  = []

            current_len = -1
            for h in t.table:
                L = h.bits
                code = h.reverse_symbol 
                
                if L != current_len:
                    min_code[L] = code
                    base_idx[L] = len(symbols)
                    current_len = L
                
                max_code[L] = code
                symbols.append(h.code)

            for L in range(1, 21):
                self.write_reg(TABLE_BASE + 0x000 + (L * 4), min_code[L])
                self.write_reg(TABLE_BASE + 0x100 + (L * 4), max_code[L])
                self.write_reg(TABLE_BASE + 0x200 + (L * 4), base_idx[L])

            for idx, sym in enumerate(symbols):
                self.write_reg(TABLE_BASE + 0x400 + (idx * 4), sym)

    def execute_dma(self, bitstream_bytes):
        """
        Conceptual DMA trigger. In a real environment (like PYNQ), 
        this uses Xilinx XAxiDma to send bits and receive 16-bit symbols.
        """
        self.write_reg(0x0FFC, 1) # Set START register
        # TX DMA: send `bitstream_bytes` to HW AXI-Stream Input
        # RX DMA: receive `decoded_symbols` (array of uint16) from HW AXI-Stream Output
        # return decoded_symbols
        pass

# ==========================================
# REPLACEMENT FOR THE MAIN HUFFMAN LOOP
# Location: Inside decode_huffman_block()
# ==========================================

    hw_driver = HuffmanAcceleratorDriver()
    hw_driver.configure_hardware(tables, selectors_list)
    
    # Extract remaining raw bytes from the file to send to DMA
    remaining_bytes = b.f.read() 
    
    # hw_symbols contains the raw integers (0 to 258) decoded by the RTL
    hw_symbols = hw_driver.execute_dma(remaining_bytes)

    # Software processes only the heavily optimized MTF and RUN logic
    repeat = repeat_power = 0
    buffer = []
    
    for r in hw_symbols:
        if 0 <= r <= 1: # RUNA or RUNB
            if repeat == 0:
                repeat_power = 1
            repeat += repeat_power << r
            repeat_power <<= 1
            continue
        elif repeat > 0:
            buffer.append(favourites[0] * repeat)
            repeat = 0
            
        if r == symbols_in_use - 1: # End of Block marker
            break
        else:
            o = favourites[r - 1]
            move_to_front(favourites, r - 1)
            buffer.append(o)

    # Continue with BWT reverse as usual...
    nt = nearly_there = bwt_reverse(b"".join(buffer), pointer)