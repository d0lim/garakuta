#!/usr/bin/perl
# Loads the now-playing helper library into this Apple-signed interpreter; the library does all the work.
# Usage: perl nowplaying.pl /path/to/libNowPlayingBridge.dylib
use strict;
use warnings;
use DynaLoader;
my $library = $ARGV[0] or die "usage: nowplaying.pl <library>\n";
DynaLoader::dl_load_file($library, 0) or die "cannot load $library: " . DynaLoader::dl_error() . "\n";
# Not reached in streaming mode; the library's constructor runs until the parent exits.
sleep 1 while 1;
