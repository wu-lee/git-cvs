package MyTest;
use Exporter qw(import);

our @EXPORT_OK = qw(barf git_cvs);

sub barf {
    my $file = shift;
    die "can't open $file: $!" 
        unless open my $fh, '>', $file;
    print $fh @_;
    close $fh;
}

sub git_cvs {
    die "can't run git-cvs: $!" unless open my $fh, '|-', "git-cvs", @_;
    my $out = join "", <$fh>;
    close $fh;
    return $out;
}


1;
