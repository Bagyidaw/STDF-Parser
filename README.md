# STDF-Parser

STDF v4 is widely used data log format and generated by various test equipments.
Here is the 1st implementation that I know of, that implements reading STDF records in pure perl with no other external module dependencies!

The objective of library is to be portable, efficient, correct. It is written in perl and min perl version requirement is only 5.12!

The implementation is in simple and straightforward perlish style and API is kept simple as well.

The performance is great, parsing large file with millions and millions of records can be accomplished in reasonble time.

This library is suitable for developing glue application that loads STDF to some other data formats, or simple analysis/summary report generation application.


I will publish applications that make use of this module in near future.

