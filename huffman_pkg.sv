
package huffman_pkg;

    // A single length-limit entry
    typedef struct packed {
        logic [19:0] min_code;
        logic [19:0] max_code;
        logic [8:0]  base_idx;
    } huff_cfg_t;

    // The full configuration matrix: 6 tables x 20 lengths
    // (Note: length 0 is invalid in Huffman, so we use indices 1 to 20. 
    // We size the array [0:20] for direct 1-to-1 array indexing).
    typedef huff_cfg_t huff_cfg_array_t [0:5][0:20];

endpackage