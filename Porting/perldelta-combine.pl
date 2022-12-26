#!perl
#use 5.036; # we want to be able to run this with non-blead too :-/
use 5.020;
use strict;
use warnings;
use feature 'signatures';
use feature 'say';
no warnings 'experimental::signatures';
use Getopt::Long;
use Pod::Usage;
use Pod::Simple::SimpleTree;
use Text::Wrap;
use Algorithm::Diff;

=head1 USAGE

  # merge the fragments in pod/perldelta into pod/perldelta.pod
  perl Porting/perldelta-combine.pl

=head1 SYNOPSIS

perldelta-combine.pl -f pod/perldelta.pod pod/perldelta/*.pod

=head1 OPTIONS

=item B<--file>

Specify the file to modify instead of C<pod/perldelta.pod>.

=item B<--target>

Specify the name of the output file instead of modifying the input file.

=item B<--dry-run>

Do not modify the output file.

=head1 DESCRIPTION

To prevent merge conflicts when two branches contain changes to perldelta.pod,
such changes can be stored in the directory pod/perldelta/ as separate files.

This script merges these separate files into pod/perldelta.pod and outputs
the commands to clean up after the merge.

Each fragment is supposed to have the following structure:

  =head1 <section name>

  =head2 <subsection name or item>

Alternatively if the subsection contains a list, the perldelta fragment must
have a list itself. This list is then appended to the existing list.

  =over

  =item X

  =back

If the tool detects that an item was already merged, it will not add the
merged items twice.

=cut

GetOptions(
    'help|h'   => \my $help,
    'f|file=s' => \my $perldelta,
    't|target=s' => \my $perldelta_target,
    'n|dry-run' => \my $dry_run,
    'c|columns=i' => \my $numcols,
) or pod2usage(2);
pod2usage(1) if $help;

$perldelta //= 'pod/perldelta.pod';
$perldelta_target //= $perldelta;
$numcols //= 79;

my @items = @ARGV;
if(! @items) {
    @items = glob 'pod/perldelta/*.pod';
}
@items = sort @items;

my ($org, $encoding, $content) = pod_tree( $perldelta );

# Merge the perldelta/*.pod entries
for my $item ( @items ) {
    my (undef, $item_encoding, $item_content) = pod_tree( $item );

    my @sections = find_element($item_content, 'head1', undef);
    die "Too many top-level sections in $item"
        if @sections > 1;
    my $section = $sections[0];
    my $name = $section->[2];

    my @target = find_element( $content, 'head1', $name );
    die "Too many top-level sections named '$name' in $perldelta"
        if @target > 1;

    say "Updating $name";

    my $target_idx = 2;
    while( $content->[$target_idx] != $target[0] ) {
        $target_idx++;
    }
    $target_idx++;

    # Now, merge the structure by walking down the item until we
    # know what to do:
    my ( $type, $info, @items ) = @$item_content;
    my ($_section,$list) = @items;
    my ($list_type, undef, @append_items) = @$list;

    while( $content->[$target_idx]->[0] ne $list_type ) {
        $target_idx++;
        die "Looking for '$list_type' but couldn't find it in $perldelta:$name"
            if( $target_idx > @$content );
    };
    my $other_list = $content->[$target_idx];
    my( $ltype, $linfo, @existing_items ) = @$other_list;

    # Check whether the item is already in the list:
    for my $new_item ($append_items[0]) {
        my $head = pod_from_tree($new_item);
        my $is_duplicate;
        for my $o (@existing_items) {
            my $existing_head = pod_from_tree($o);
            if( $head eq $existing_head ) {
                warn "$item: $head already exists in $perldelta line $o->[1]->{start_line}, ignored\n";
                $is_duplicate = 1;
            };
        }
        if( ! $is_duplicate) {
            push @{ $other_list }, @append_items;
        }
    };

}

# Generate the output file again
my $output = pod_from_tree($content);

# Remove trailing whitespace
$output =~ s/[ \t]+$//mg;

if( $dry_run ) {
    if( $output ne $content ) {
        say "Would modify $perldelta_target";
    }
} else {
    update_file( $perldelta_target, $output );
}

# We should check here that we do not remove lines
# ... since the new sections should only add stuff
## Show the diff
#if($content ne $output) {
#    my $diff = Algorithm::Diff->new([split /\r?\n/, $org], [split /\r?\n/, $output]);
#    $diff->Base(1);
#    while(  $diff->Next()  ) {
#        next   if  $diff->Same();
#        my $sep = '';
#        if(  ! $diff->Items(2)  ) {
#            printf "%d,%dd%d\n",
#                $diff->Get(qw( Min1 Max1 Max2 ));
#        } elsif(  ! $diff->Items(1)  ) {
#            printf "%da%d,%d\n",
#                $diff->Get(qw( Max1 Min2 Max2 ));
#        } else {
#            $sep = "---\n";
#            printf "%d,%dc%d,%d\n",
#                $diff->Get(qw( Min1 Max1 Min2 Max2 ));
#        }
#        print "< $_\n"   for  $diff->Items(1);
#        print $sep;
#        print "> $_\n"   for  $diff->Items(2);
#    }
#    exit 1;
#}

sub pod_tree( $filename ) {
    my $org = do { open my $fh, '<:raw', $filename
                       or die "Couldn't read '$filename': $!";
                   local $/;
                   <$fh>
                 };
    my $parser = Pod::Simple::SimpleTree->new->parse_string_document($org);
    my $content = $parser->root;
    my $encoding = $parser->encoding;

    return ($org, $encoding, $content);
}

sub find_element( $tree, $_type, $_value ) {
    my @res;
    my ($type, $info, @items) = @$tree;

    for my $item (@items) {
        if( ref $item ) {
            my( $type, $info, @items ) = @$item;
            if( $type eq $_type ) {
                if( defined $_value ? $_value eq $items[0] : 1 ) {
                    push @res, $item
                }
            };
            push @res, find_element( $item, $_type, $_value );
        }
    }

    @res
}

sub pod_from_subtree($parent_type, @items) {
    my $res = '';
    for my $item (@items) {
        if( ! ref $item ) {
            if( $parent_type eq 'Para' ) {
                # Pod::Simple munges ".  " to ". " , so let's revert that:
                $item =~ s/\.\s+$/./g;
                $item =~ s/(?<!etc|i\.e)\. (?=\w)/.  /g;
            }
            $res .= $item;
        } elsif( ref $item eq 'ARRAY' ) {
            #warn "Descending into " . $item->[0];
            $res .= pod_from_tree( $item );
        } else {
            die "Unknown element $item in data structure";
        }
    }
    return $res
}

sub wrapped_pod( $text ) {
    local $Text::Wrap::columns = $numcols;
    local $Text::Wrap::unexpand;
    local $Text::Wrap::huge = 'overflow';
    # Don't break within L<...>
    local $Text::Wrap::break = qr/\s(?![^<]+>)/;
    return wrap('','',$text);
}

# ... meh - we want to smartly wrap L<...> or other long stuff
#     so it lives on a single line
sub pod_from_tree($tree) {
    my $res = '';
    my $postfix = '';
    my ($type,$info,@items) = @$tree;

    if( $type eq 'Document') {
        # Pod::Simple doesn't deliver =encoding but passes that data in
        # a separate accessor...
        $res .= "=encoding $encoding"
             .  pod_from_subtree($type, @items)
             .  "\n\n=cut\n";
    } elsif( $type eq 'Para' ) {
        $res .= "\n\n"
             . wrapped_pod(pod_from_subtree($type => @items));
    } elsif( $type eq 'Verbatim' ) {
        $res .= "\n\n"
             . pod_from_subtree($type => @items);
    } elsif( $type eq 'over-text' ) {
        $res .= "\n\n=over " . $info->{indent}
             . pod_from_subtree($type => @items)
             . "\n\n=back";
    } elsif( $type eq 'item-text' ) {
        $res .= "\n\n=item "
             . wrapped_pod( pod_from_subtree($type => @items));
    } elsif( $type eq 'over-bullet' ) {
        $res .= "\n\n=over " . $info->{indent}
             . pod_from_subtree($type => @items)
             . "\n\n=back";
    } elsif( $type eq 'item-bullet' ) {
        $res .= "\n\n=item *\n\n"
             . wrapped_pod( pod_from_subtree($type => @items));
    } elsif( $type =~ /^head\d+$/ ) {
        $res .= "\n\n=$type "
             . pod_from_subtree($type => @items);
    } elsif( $type =~ /^[BCFL]$/ ) {
        if( $type eq 'L' ) {
            # Convert quoted section back to Pod syntax ?!
            $res .= 'L<' . $info->{raw} . '>';
        } else {
            my $content = pod_from_subtree($type => @items);
            $res .= "$type<$content>";
        }
    } else {
        use Data::Dumper;
        die "Unknown type '$type' in " . Dumper $tree;
    }

    return $res;
}

sub update_file( $filename, $new_content ) {
    my $content;
    if( -f $filename ) {
        open my $fh, '<:raw:encoding(UTF-8)', $filename
            or die "Couldn't read '$filename': $!";
        local $/;
        $content = <$fh>;
    };

    if( $content ne $new_content ) {
        if( open my $fh, '>:raw:encoding(UTF-8)', $filename ) {
            print $fh $new_content;
        } else {
            warn "Couldn't (re)write '$filename': $!";
        };
    };
}

# in our output, we should only add lines, and never change or remove lines:

