## Nucleosome model from Kaplan et al. Nature 2009

__Full paper details:__

_The DNA-encoded nucleosome organization of a eukaryotic genome_  
Kaplan N*, Moore IK*, Fondufe-Mittendorf Y, Gossett AJ, Tillo D, Field Y, LeProust EM, Hughes TR, Lieb JD, Widom J, Segal E.  
Nature, 2009 458(7236):362-6. doi: 10.1038/nature07667

Major contributions to this code by Yair Field, Yaniv Lubling, Eran Segal

__Description:__

The probabilistic model was trained on MNase-Seq data measure on chicken histones reconstituted onto yeast genomic DNA at sub-physiological concentration (4:10 histone to DNA).

The code in this repository to the code previously hosted on the Segal Lab website: https://genie.weizmann.ac.il/pubs/nucleosomes08/index.html

Data is provided at GEO GSE13622 (https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE13622) and https://genie.weizmann.ac.il/pubs/nucleosomes08/index.html

__Running details:__

This is the linux 64 bit version.

1. Run `make install`. 
2. To test an example, run:
 
`perl nucleosome_prediction.pl -t title -s input.fa -c 0.03 -temp 1 -tab -p out`
 
These are the temperature and concentration parameters used in the paper to match in-vitro reconstituted nucleosome organization (i.e. low concentration; depending on aim, a higher concentration value may be appropriate). This should create a file `out.tab` containing the output.

__Standalone executable:__

Running `make standalone` builds a single executable that has everything needed to run the predictions packed into it, including Perl (it's built with [PAR::Packer](https://metacpan.org/dist/PAR-Packer)). It doesn't need `make install` or anything else from this repository, so you can copy it to other machines. Its name gives the version number (from the `VERSION` file) and the system it was built for. For example, version 1.0.0 built on Rocky Linux 10 is `dist/nucleosome_prediction-1.0.0-el10-x86_64` (`el10` covers RHEL, Rocky and AlmaLinux 10). On other distributions the `el10` part is their name and version instead, e.g. `ubuntu24.04`. It takes the same options as `nucleosome_prediction.pl`:

`dist/nucleosome_prediction-1.0.0-el10-x86_64 -t title -s input.fa -c 0.03 -temp 1 -tab -p out`

1. The first build downloads PAR::Packer and installs it in `standalone/.perl5`, so it needs internet access. Each build is tested by running the new executable on `input.fa` and comparing the results with the example output files.
2. The executable only runs on Linux systems similar to the one it was built on. For example, if you build it on Rocky Linux 10 it needs glibc 2.38 or newer and `libcrypt.so.2`, so it will run on RHEL/Rocky/AlmaLinux 10 and recent Fedora but not on Debian or Ubuntu.
3. The first time it runs, it unpacks itself (about 26 MB) into `$TMPDIR/par-<user>/`. If `/tmp` is mounted `noexec`, set `PAR_GLOBAL_TMPDIR` to a directory where you can run programs.

__libstdc++.so.5:__

`map_learn_static` uses `lib/libxerces-c.so.27`, which needs `libstdc++.so.5`. Current Linux distributions don't include it any more, so a copy is included in `lib/`. Both `make install` and `make standalone` use it. It comes from the CentOS 7 package `compat-libstdc++-33-3.2.3-72.el7.x86_64` (libstdc++ from GCC 3.3.4), so it is for 64-bit x86 Linux and needs glibc 2.14 or newer. It has been tested on Rocky Linux 10.2 (x86_64, AMD EPYC).

If you are building on a different system and this copy doesn't work, you need to supply your own: replace `lib/libstdc++.so.5`, or run `make standalone LIBSTDCXX5=/path/to/libstdc++.so.5`. The same goes for the other libraries in `lib/`. However, `bin/map_learn_static` is itself an x86_64 Linux program, so none of this will run on other types of CPU (e.g. ARM) or on other operating systems.

libstdc++ is licensed under the GNU GPL version 2 or later, with the libstdc++ runtime exception (see `lib/COPYING.libstdc++`). Its source code is in the CentOS 7 source package [compat-gcc-32-3.2.3-72.el7.src.rpm](https://vault.centos.org/7.9.2009/os/Source/SPackages/compat-gcc-32-3.2.3-72.el7.src.rpm).

__Troubleshooting:__

If the test output file is empty, or you get "Error: No output from map_learn_static", it is usually due to its dependence on a linked library which is now old and thus missing from some libraries. To diagnose which library is missing on your system:

1. Add the `XXX/lib/` directory to your `LD_LIBRARY_PATH` environment variable, where XXX is the folder where you installed the software (since some of the needed libraries are located there).
2. Run `XXX/bin/map_learn_static`. You will get an error message showing you which library is missing.
3. Download the missing library.

For example, if you use Centos 7, you should get an error message that you are missing `libstdc++.so.5`, and to get it you would use `yum install compat-libstdc++-33.x86_64`. `lib/` now includes a copy of `libstdc++.so.5` (see above), so you should only see this if that copy doesn't work on your system.

__Additional usage notes:__

1. Use `perl nucleosome_prediction.pl –help` for more options.
2. The code can only deal with nucleotides that are ACGT. For other nucleotides (e.g. N), one possible solution is to replace these with C, as it is relatively neutral. Still keep in mind that predictions made on such regions may be unreliable.
3. It is important to remember that concentration effects are included in the model, and these can create strong long-range positioning near boundaries. This means that it is better to make predictions on entire chromosomes and then extract specific regions of interest, or alternatively add >5 kb of flanking sequence to each region of interest in order to buffer any boundary effects.

__Contact:__

For any questions please contact Noam Kaplan noam.kaplan@technion.ac.il



