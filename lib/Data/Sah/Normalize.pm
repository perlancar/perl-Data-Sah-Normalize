package Data::Sah::Normalize;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       normalize_clset
                       normalize_schema

                       $type_re
                       $clause_name_re
                       $clause_re
                       $attr_re
                       $funcset_re
                       $compiler_re
               );

our $type_re        = qr/\A(?:[A-Za-z_]\w*::)*[A-Za-z_]\w*\z/;
our $clause_name_re = qr/\A[A-Za-z_]\w*\z/;
our $clause_re      = qr/\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/;
our $attr_re        = $clause_re;
our $funcset_re     = qr/\A(?:[A-Za-z_]\w*::)*[A-Za-z_]\w*\z/;
our $compiler_re    = qr/\A[A-Za-z_]\w*\z/;
our $clause_attr_on_empty_clause_re = qr/\A(?:\.[A-Za-z_]\w*)+\z/;

sub normalize_clset($;$) {
    my ($clset0, $opts) = @_;
    $opts //= {};

    my $clset = {};
    for my $c (sort keys %$clset0) {
        my $c0 = $c;

        my $v = $clset0->{$c};

        # ignore expression
        my $expr;
        if ($c =~ s/=\z//) {
            $expr++;
            # XXX currently can't disregard merge prefix when checking
            # conflict
            die "Conflict between '$c=' and '$c'" if exists $clset0->{$c};
            $clset->{"$c.is_expr"} = 1;
            }

        my $sc = "";
        my $cn;
        {
            my $errp = "Invalid clause name syntax '$c0'"; # error prefix
            if (!$expr && $c =~ s/\A!(?=.)//) {
                die "$errp, syntax should be !CLAUSE"
                    unless $c =~ $clause_name_re;
                $sc = "!";
            } elsif (!$expr && $c =~ s/(?<=.)\|\z//) {
                die "$errp, syntax should be CLAUSE|"
                    unless $c =~ $clause_name_re;
                $sc = "|";
            } elsif (!$expr && $c =~ s/(?<=.)\&\z//) {
                die "$errp, syntax should be CLAUSE&"
                    unless $c =~ $clause_name_re;
                $sc = "&";
            } elsif (!$expr && $c =~ /\A([^.]+)(?:\.(.+))?\((\w+)\)\z/) {
                my ($c2, $a, $lang) = ($1, $2, $3);
                die "$errp, syntax should be CLAUSE(LANG) or C.ATTR(LANG)"
                    unless $c2 =~ $clause_name_re &&
                        (!defined($a) || $a =~ $attr_re);
                $sc = "(LANG)";
                $cn = $c2 . (defined($a) ? ".$a" : "") . ".alt.lang.$lang";
            } elsif ($c !~ $clause_re &&
                         $c !~ $clause_attr_on_empty_clause_re) {
                die "$errp, please use letter/digit/underscore only";
            }
        }

        # XXX can't disregard merge prefix when checking conflict
        if ($sc eq '!') {
            die "Conflict between clause shortcuts '!$c' and '$c'"
                if exists $clset0->{$c};
            die "Conflict between clause shortcuts '!$c' and '$c|'"
                if exists $clset0->{"$c|"};
            die "Conflict between clause shortcuts '!$c' and '$c&'"
                if exists $clset0->{"$c&"};
            $clset->{$c} = $v;
            $clset->{"$c.op"} = "not";
        } elsif ($sc eq '&') {
            die "Conflict between clause shortcuts '$c&' and '$c'"
                if exists $clset0->{$c};
            die "Conflict between clause shortcuts '$c&' and '$c|'"
                if exists $clset0->{"$c|"};
            die "Clause 'c&' value must be an array"
                unless ref($v) eq 'ARRAY';
            $clset->{$c} = $v;
            $clset->{"$c.op"} = "and";
        } elsif ($sc eq '|') {
            die "Conflict between clause shortcuts '$c|' and '$c'"
                if exists $clset0->{$c};
            die "Clause 'c|' value must be an array"
                unless ref($v) eq 'ARRAY';
            $clset->{$c} = $v;
            $clset->{"$c.op"} = "or";
        } elsif ($sc eq '(LANG)') {
            die "Conflict between clause '$c' and '$cn'"
                if exists $clset0->{$cn};
            $clset->{$cn} = $v;
        } else {
            $clset->{$c} = $v;
        }

    }
    $clset->{req} = 1 if $opts->{has_req};

    # XXX option to recursively normalize clset, any's of, all's of, ...
    #if ($clset->{clset}) {
    #    local $opts->{has_req};
    #    if ($clset->{'clset.op'} && $clset->{'clset.op'} =~ /and|or/) {
    #        # multiple clause sets
    #        $clset->{clset} = map { $self->normalize_clset($_, $opts) }
    #            @{ $clset->{clset} };
    #    } else {
    #        $clset->{clset} = $self->normalize_clset($_, $opts);
    #    }
    #}

    $clset;
}

sub normalize_schema($) {
    my $s = shift;

    my $ref = ref($s);
    if (!defined($s)) {

        die "Schema is missing";

    } elsif (!$ref) {

        my $has_req = $s =~ s/\*\z//;
        $s =~ $type_re or die "Invalid type syntax $s, please use ".
            "letter/digit/underscore only";
        return [$s, $has_req ? {req=>1} : {}];

    } elsif ($ref eq 'ARRAY') {

        my $t = $s->[0];
        my $has_req = $t && $t =~ s/\*\z//;
        if (!defined($t)) {
            die "For array form, at least 1 element is needed for type";
        } elsif (ref $t) {
            die "For array form, first element must be a string";
        }
        $t =~ $type_re or die "Invalid type syntax $s, please use ".
            "letter/digit/underscore only";

        my $clset0;
        my $extras;
        if (defined($s->[1])) {
            if (ref($s->[1]) eq 'HASH') {
                $clset0 = $s->[1];
                $extras = $s->[2];
                die "For array form, there should not be more than 3 elements"
                    if @$s > 3;
            } else {
                # flattened clause set [t, c=>1, c2=>2, ...]
                die "For array in the form of [t, c1=>1, ...], there must be ".
                    "3 elements (or 5, 7, ...)"
                        unless @$s % 2;
                $clset0 = { @{$s}[1..@$s-1] };
            }
        } else {
            $clset0 = {};
        }

        # check clauses and parse shortcuts (!c, c&, c|, c=)
        my $clset = normalize_clset($clset0, {has_req=>$has_req});
        if (defined $extras) {
            die "For array form with 3 elements, extras must be hash"
                unless ref($extras) eq 'HASH';
            die "Extras must be empty hashref (Sah 0.9.47)" if keys %$extras;
            # we remove extras to comply with Sah 0.9.47+
            return [$t, $clset];
        } else {
            return [$t, $clset];
        }
    }

    die "Schema must be a string or arrayref (not $ref)";
}

1;
# ABSTRACT: Normalize Sah schema

=head1 SYNOPSIS

 use Data::Sah::Normalize qw(normalize_clset normalize_schema);

 my $nclset = normalize_clset({'!a'=>1}); # -> {a=>1, 'a.op'=>'not'}
 my $nsch   = normalize_schema("int");    # -> ["int", {}]


=head1 DESCRIPTION

This often-needed functionality is split from the main L<Data::Sah> to keep it
in a small and minimal-dependencies package.


=head1 FUNCTIONS

=head2 normalize_clset($clset) => HASH

Normalize a clause set (hash). Return a shallow copy of the original hash. Die
on failure.

TODO: option to recursively normalize clause which contains sah clauses (e.g.
C<of>).

=head2 normalize_schema($sch) => ARRAY

Normalize a Sah schema (scalar or array). Return an array. Produce a 2-level
copy of schema, so it's safe to add/delete/modify the normalized schema's clause
set, but clause set's values are still references to the original. Die on
failure.

TODO: recursively normalize clause which contains sah clauses (e.g. C<of>).


=head1 SEE ALSO

L<Sah>, L<Data::Sah>

=cut
