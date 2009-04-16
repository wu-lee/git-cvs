package MyTest::Dirs;
use strict;
use warnings;
use FindBin qw($Bin $Script);
use File::Spec;
use File::Path qw(mkpath rmtree);

=head2 C<< $obj = $class->new(%params) >>

Given parameters including:

  base => $base_dir,

  data => [ddir1 => relpath3, ddir2 => relpath4 ...]

  test => [tdir1 => relpath1, tdir2 => relpath2 ...]

Uses C<base> as a base dir in which to find data dirs C<relpathN> (which
are checked to exist), and in which to re-create fresh test dirs
C<relpathM>.

If C<base> is not given, uses the name of the invoking script, with
any leading digits or periods stripped, and any trailing ".t"
stripped.

Retuns a hash-based object which keys the names C<ddirN> and C<tdirN>
to the appropriate paths constructed from C<$base_dir> and the
appropriate C<relpath>.

=cut
                               
sub new {
    my $class = shift;
    my %param = @_;
    my $base = $param{base};
    ($base) = $Script =~ /^[\d.]*(.*?)(\.t)?$/
        unless defined $base;

    my $self = bless {
        data_dir => File::Spec->catdir($Bin,'data', $base),
        temp_dir => File::Spec->catdir($Bin,'temp', $base),
    }, $class;
    rmtree $self->{temp_dir};

    # validate the data directories exist
    if (my $data = $param{data}) {
        while(my ($name, $dir) = splice @$data, 0, 2) {
            die "Can't use dir name '$name': already in use as '$self->{$name}'"
                if exists $self->{$name};

            $dir = File::Spec->catdir($self->{data_dir}, $dir);
            die "No such data directory '$dir'"
                unless -d $dir;
            $self->{$name} = $dir;
        }
    }

    # recreate the temp directories
    if (my $temp = $param{temp}) {
        while(my ($name, $dir) = splice @$temp, 0, 2) {
            die "Can't use dir name '$name': already in use as '$self->{$name}'"
                if exists $self->{$name};

            $dir = File::Spec->catdir($self->{temp_dir}, $dir);
            rmtree $dir if -e $dir;
            die "Can't delete '$dir'"
                if -e $dir;
            mkpath $dir;
            die "Can't create '$dir'"
                unless -d $dir;
            $self->{$name} = $dir;
        }
    }

    return $self;
}

sub hash { %{ shift->new(@_) } }

1;
