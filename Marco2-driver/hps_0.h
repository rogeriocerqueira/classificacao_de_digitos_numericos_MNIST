#ifndef HPS_0_H
#define HPS_0_H

/* data_in: PIO de saída, 32 bits */
#define DATA_IN_BASE           0x40
#define DATA_IN_SPAN           16
#define DATA_IN_DATA_WIDTH     32
#define DATA_IN_HAS_IN         0
#define DATA_IN_HAS_OUT        1
#define DATA_IN_HAS_TRI        0

/* data_out: PIO de entrada, 32 bits */
#define DATA_OUT_BASE          0x50
#define DATA_OUT_SPAN          16
#define DATA_OUT_DATA_WIDTH    32
#define DATA_OUT_HAS_IN        1
#define DATA_OUT_HAS_OUT       0
#define DATA_OUT_HAS_TRI       0

/* ctrl: PIO de saída, 3 bits */
#define CTRL_BASE              0x60
#define CTRL_SPAN              16
#define CTRL_DATA_WIDTH        3
#define CTRL_HAS_IN            0
#define CTRL_HAS_OUT           1
#define CTRL_HAS_TRI           0

#endif
