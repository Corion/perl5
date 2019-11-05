#!perl -w

use strict;
use warnings;
use Test::More;
use Devel::Peek;

BEGIN {use_ok('XS::APItest')};

for my $test (
    ["\x{12}\x{34}\x{56}\x{78}\x{9A}\x{BC}\x{DE}\x{F0}",
    "0x3412","0x78563412","0xf0debc9a78563412"],
    ["\x{F0}\x{E1}\x{D2}\x{C3}\x{B4}\x{A5}\x{96}\x{87}",
    "0xe1f0","0xc3d2e1f0","0x8796a5b4c3d2e1f0"],
) {
    my ($str,$want16,$want32,$want64)= @$test;
    my $input= join " ", map { sprintf "%02x", ord($_) } split //, $str;
    my $hex16= sprintf "0x%04x",XS::APItest::HvMacro::u8_to_u16_le($str);
    is($hex16,$want16,"U8TO16_LE works as expected (hex bytes:".substr($input,0,4+1).")");
    my $hex32= sprintf "0x%08x",XS::APItest::HvMacro::u8_to_u32_le($str);
    is($hex32,$want32,"U8TO32_LE works as expected (hex bytes:".substr($input,0,8+3).")");
    my $hex64= sprintf "0x%016x",XS::APItest::HvMacro::u8_to_u64_le($str);
    is($hex64,$want64,"U8TO64_LE works as expected (hex bytes:".substr($input,0,16+7).")");
}
done_testing();


