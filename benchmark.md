```sh
❯ zig build bench

================================================================================
MessagePack Benchmark Suite
================================================================================

Basic Types:
--------------------------------------------------------------------------------
                               Nil Write |  1000000 iterations |       23 ns/op | 43478260 ops/sec
                                Nil Read |  1000000 iterations |    12484 ns/op |    80102 ops/sec
                              Bool Write |  1000000 iterations |       27 ns/op | 37037037 ops/sec
                               Bool Read |  1000000 iterations |    11992 ns/op |    83388 ops/sec
                         Small Int Write |  1000000 iterations |       27 ns/op | 37037037 ops/sec
                          Small Int Read |  1000000 iterations |    12429 ns/op |    80456 ops/sec
                         Large Int Write |  1000000 iterations |       48 ns/op | 20833333 ops/sec
                          Large Int Read |  1000000 iterations |    11975 ns/op |    83507 ops/sec
                             Float Write |  1000000 iterations |       46 ns/op | 21739130 ops/sec
                              Float Read |  1000000 iterations |    12382 ns/op |    80762 ops/sec

Strings:
--------------------------------------------------------------------------------
            Short String Write (5 bytes) |   500000 iterations |    21283 ns/op |    46985 ops/sec
             Short String Read (5 bytes) |   500000 iterations |    38483 ns/op |    25985 ops/sec
        Medium String Write (~300 bytes) |   100000 iterations |    26060 ns/op |    38372 ops/sec
         Medium String Read (~300 bytes) |   100000 iterations |    40271 ns/op |    24831 ops/sec

Binary Data:
--------------------------------------------------------------------------------
           Small Binary Write (32 bytes) |   500000 iterations |    23217 ns/op |    43071 ops/sec
            Small Binary Read (32 bytes) |   500000 iterations |    39784 ns/op |    25135 ops/sec
                Large Binary Write (1KB) |   100000 iterations |    33540 ns/op |    29815 ops/sec
                 Large Binary Read (1KB) |   100000 iterations |    49550 ns/op |    20181 ops/sec

Arrays:
--------------------------------------------------------------------------------
         Small Array Write (10 elements) |   100000 iterations |    56802 ns/op |    17605 ops/sec
          Small Array Read (10 elements) |   100000 iterations |   120598 ns/op |     8292 ops/sec
       Medium Array Write (100 elements) |    50000 iterations |    86305 ns/op |    11586 ops/sec
        Medium Array Read (100 elements) |    50000 iterations |   179349 ns/op |     5575 ops/sec

Maps:
--------------------------------------------------------------------------------
            Small Map Write (10 entries) |   100000 iterations |   303730 ns/op |     3292 ops/sec
             Small Map Read (10 entries) |   100000 iterations |   450047 ns/op |     2221 ops/sec
           Medium Map Write (50 entries) |    50000 iterations |   942602 ns/op |     1060 ops/sec
            Medium Map Read (50 entries) |    50000 iterations |  1456101 ns/op |      686 ops/sec

Extension Types:
--------------------------------------------------------------------------------
                    EXT Write (16 bytes) |   500000 iterations |    24203 ns/op |    41317 ops/sec
                     EXT Read (16 bytes) |   500000 iterations |    40463 ns/op |    24713 ops/sec

Timestamps:
--------------------------------------------------------------------------------
                       Timestamp32 Write |  1000000 iterations |       74 ns/op | 13513513 ops/sec
                        Timestamp32 Read |  1000000 iterations |    12940 ns/op |    77279 ops/sec
                       Timestamp64 Write |  1000000 iterations |       74 ns/op | 13513513 ops/sec
                        Timestamp64 Read |  1000000 iterations |    12427 ns/op |    80469 ops/sec

Complex Structures:
--------------------------------------------------------------------------------
                  Nested Structure Write |    50000 iterations |   115840 ns/op |     8632 ops/sec
                   Nested Structure Read |    50000 iterations |   239723 ns/op |     4171 ops/sec
                       Mixed Types Write |    50000 iterations |    88667 ns/op |    11278 ops/sec
                        Mixed Types Read |    50000 iterations |   185971 ns/op |     5377 ops/sec

================================================================================
Benchmark Complete
================================================================================
❯ zig build bench -Doptimize=ReleaseFast

================================================================================
MessagePack Benchmark Suite
================================================================================

Basic Types:
--------------------------------------------------------------------------------
                               Nil Write |  1000000 iterations |        6 ns/op | 166666666 ops/sec
                                Nil Read |  1000000 iterations |     4359 ns/op |   229410 ops/sec
                              Bool Write |  1000000 iterations |        2 ns/op | 500000000 ops/sec
                               Bool Read |  1000000 iterations |     4635 ns/op |   215749 ops/sec
                         Small Int Write |  1000000 iterations |        7 ns/op | 142857142 ops/sec
                          Small Int Read |  1000000 iterations |     4710 ns/op |   212314 ops/sec
                         Large Int Write |  1000000 iterations |        5 ns/op | 200000000 ops/sec
                          Large Int Read |  1000000 iterations |     4978 ns/op |   200883 ops/sec
                             Float Write |  1000000 iterations |        4 ns/op | 250000000 ops/sec
                              Float Read |  1000000 iterations |     4487 ns/op |   222866 ops/sec

Strings:
--------------------------------------------------------------------------------
            Short String Write (5 bytes) |   500000 iterations |     6876 ns/op |   145433 ops/sec
             Short String Read (5 bytes) |   500000 iterations |     9888 ns/op |   101132 ops/sec
        Medium String Write (~300 bytes) |   100000 iterations |    10189 ns/op |    98145 ops/sec
         Medium String Read (~300 bytes) |   100000 iterations |    14305 ns/op |    69905 ops/sec

Binary Data:
--------------------------------------------------------------------------------
           Small Binary Write (32 bytes) |   500000 iterations |     9787 ns/op |   102176 ops/sec
            Small Binary Read (32 bytes) |   500000 iterations |     9506 ns/op |   105196 ops/sec
                Large Binary Write (1KB) |   100000 iterations |     6748 ns/op |   148192 ops/sec
                 Large Binary Read (1KB) |   100000 iterations |     8847 ns/op |   113032 ops/sec

Arrays:
--------------------------------------------------------------------------------
         Small Array Write (10 elements) |   100000 iterations |     8685 ns/op |   115141 ops/sec
          Small Array Read (10 elements) |   100000 iterations |    15166 ns/op |    65936 ops/sec
       Medium Array Write (100 elements) |    50000 iterations |    16765 ns/op |    59648 ops/sec
        Medium Array Read (100 elements) |    50000 iterations |    29700 ns/op |    33670 ops/sec

Maps:
--------------------------------------------------------------------------------
            Small Map Write (10 entries) |   100000 iterations |    35803 ns/op |    27930 ops/sec
             Small Map Read (10 entries) |   100000 iterations |    44254 ns/op |    22596 ops/sec
           Medium Map Write (50 entries) |    50000 iterations |    48868 ns/op |    20463 ops/sec
            Medium Map Read (50 entries) |    50000 iterations |    68684 ns/op |    14559 ops/sec

Extension Types:
--------------------------------------------------------------------------------
                    EXT Write (16 bytes) |   500000 iterations |     6597 ns/op |   151584 ops/sec
                     EXT Read (16 bytes) |   500000 iterations |     8930 ns/op |   111982 ops/sec

Timestamps:
--------------------------------------------------------------------------------
                       Timestamp32 Write |  1000000 iterations |        5 ns/op | 200000000 ops/sec
                        Timestamp32 Read |  1000000 iterations |     4397 ns/op |   227427 ops/sec
                       Timestamp64 Write |  1000000 iterations |        5 ns/op | 200000000 ops/sec
                        Timestamp64 Read |  1000000 iterations |     4289 ns/op |   233154 ops/sec

Complex Structures:
--------------------------------------------------------------------------------
                  Nested Structure Write |    50000 iterations |    13055 ns/op |    76599 ops/sec
                   Nested Structure Read |    50000 iterations |    15526 ns/op |    64408 ops/sec
                       Mixed Types Write |    50000 iterations |    13108 ns/op |    76289 ops/sec
                        Mixed Types Read |    50000 iterations |    18246 ns/op |    54806 ops/sec

================================================================================
Benchmark Complete
================================================================================
```

