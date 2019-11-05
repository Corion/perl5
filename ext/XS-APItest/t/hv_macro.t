#!perl -w

use strict;
use warnings;
use Test::More;
use Devel::Peek;

BEGIN {use_ok('XS::APItest')};

my $str="\x{12}\x{34}\x{56}\x{78}\x{9A}\x{BC}\x{DE}\x{F0}";

diag "hex input:", join(" ", unpack("H*",$str)),"\n";
my $hex16= sprintf "0x%04x",XS::APItest::HvMacro::u8_to_u16_le($str);
is($hex16,"0x3412","U8TO16_LE works as expected");
my $hex32= sprintf "0x%08x",XS::APItest::HvMacro::u8_to_u32_le($str);
is($hex32,"0x78563412","U8TO32_LE works as expected");
my $hex64= sprintf "0x%016x",XS::APItest::HvMacro::u8_to_u64_le($str);
is($hex64,"0xf0debc9a78563412","U8TO64_LE works as expected");
done_testing();


