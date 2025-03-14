# EESM6000C Lab 3
Student ID: 20726557

## Function Specification
>y[t] = Σ (h[i] * x[t - i]）

## Design Specification
* Data_Width 32bit (integer)
* Tap_Num 11
* Data_Num TBD – Based on the size of the data file
* Interface
  - axilite: configuration data_in:
  - axi-stream: stream ( Xn ), stream (Yn)
* Using one Multiplier and one Adder:
* Note: Multiplication and Addition are run in separate pipeline cycle
* Note: Don’t use DSP, use Xilinx directive (* use_dsp = "no" *)
* Shift registers implemented with SRAM ( Shift_RAM, size = 10 DW)
* Tap coefficient implemented with SRAM ( Tap_RAM = 11 DW ), initialized by axilite write
* Operation ( Refer to: Configuration Register Address map )
  - Program ap_start to initiate FIR engine
  - Stream in Xn. The rate is varied by testbench. axi-stream tvalid/tready for flow control.
  - Stream out Yn, the rate of output transfer is varied by testbench. axi-stream tvalid/tready for flow control.

## HackMD Report
https://hackmd.io/@JokerAnthonio/Hy-_y7Jh1e
