The bbl.u540 image is for the HiFive Unleashed board.
It is built from this repository:

https://github.com/rwmjones/fedora-riscv-kernel/tree/sifive_u540

(NB: the sifive_u540 branch)

You MUST:

(1) Set up an NBD server.  See the README file in the github link above.

(2) Edit the bbl.u540 image and carefully replace the IP address of
the NBD server.  Be careful not to make the command line longer or
shorter.

(3) Copy the bbl.u540 over the first partition of the SD card.
