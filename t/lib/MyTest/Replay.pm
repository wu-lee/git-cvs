package MyTest::Replay;
use strict;
use warnings;
use Test::Builder;
use File::Path qw(rmtree);
use Cwd ();

our $Test = Test::Builder->new;

# $obj = $class->new($path)
#
# Creates a Replay instance which operates on $path.
sub new {
    my $class = shift;
    my %param = @_;
    my $path = $param{path};

    die "No such dir $path\n"
        unless -d $path;

    # 'exe_map' should be a hash mapping exectuable names to explicit
    # paths to use.  It is optional, if no mapping is given for an
    # executable, the bare name is used and it is resoved via $PATH
    my $exe_map = {};
    if (exists $param{exe_map}) {
        $exe_map = $param{exe_map};
        die "exe_map parameter must be a hashref"
            unless ref $exe_map eq 'HASH';

        # Check any explicit paths actually exist.
        foreach my $exe_name (keys %$exe_map) {
            my $exe_path = $exe_map->{$exe_name};
            die "No executable exists at '$exe_path'"
                unless -x $exe_path;
        }
    }

    return bless { path  => $path, exe_map => $exe_map }, $class;
}



# $obj->playback(@actions)
#
# Takes in a list of strings, and interprets them as additions,
# removals, or commands.
#
# Additions have the form "+<relpath> <content>" and create a file at
# <relpath> with content <content> (or a dir if <relpath> ends with
# "/").
#
# Removals have the form "-<relpath>" and remove a file or directory
# at <relpath>
#
# Invokations have the form "*<command> <args>" and perform some action,
# such as a cvs command.
#
# Tests for existance or non-existance of some path (relative to the
# repository root) have the form "?<path>" and "!<path>" respectively.
#
# Blank lines, and comments - lines beginning with a hash '#'
# character (with optional preceeding whitespace) - are ignored.
#
my $path_re = qr{[\w.~/,+-]+};

sub playback {
    my $self = shift;
    my @actions = split "\n", shift;

    # make sure errors are reported at the right level
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    for (@actions) {
        
        s/^\s+//s;
        s/\s+$//s;
        
        /^\s*$/ and next;

        print "$_\n";

        /^\s*#/ and next;

        /^([!?])\s*($path_re)/ and do {
            $1 eq '?' ? 
                $self->assert_path($2)   : 
                $self->assert_no_path($2);
            next;
        };

        m!^\+($path_re)\s*(.*)! and do {
            $self->append($1, $2);
            next;
        };

        /^-(.*)/ and do {
            $self->remove($1);
            next;
        };

        /^\*\s*(\S.*)/ and do {
            $self->invoke($1);
            next;
        };

        die "Invalid line:\n$_\n";
    }
}

sub expand {
    my $self = shift;
    my $dir = shift;
    die "Invalid subdir '$dir'" 
        if $dir =~ /[.]{1,2}/
        || $dir =~ m!^\s*/!;
        
    return File::Spec->catdir($self->{path}, $dir);
}

sub append {
    my $self = shift;
    my ($vol, $reldir, $file) = File::Spec->splitpath(shift);
    my $dir = $self->expand($reldir);

    mkdir $dir;
    return unless $file;

    my $content = shift;
    my $path = File::Spec->catpath($vol, $dir, $file);
    open my $fh, ">>", $path
        or die "Failed to open '$file' in $reldir: $!";
    print $fh $content, "\n" 
        if defined $content;
    close $file;
}

sub remove {
    my $self = shift;
    my ($vol, $reldir, $file) = File::Spec->splitpath(shift);
    my $dir = $self->expand($reldir);

    my $path = File::Spec->catpath($vol, $dir, $file);
    rmtree $path;  
}


sub assert {
    my $self = shift;
    my ($bool, $mess) = @_;

    $Test->ok($bool, $mess);    
}

sub assert_path {
    my $self = shift;
    my $relpath = shift;
    my $path = File::Spec->catdir($self->{path}, $relpath);
    my $dir = (File::Spec->splitdir($self->{path}))[-1];
    my (undef, undef, $file) = File::Spec->splitpath($path);

    # make sure errors are reported at the right level
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    if ($file) {
        $self->assert(-f $path, "file '$relpath' exists in $dir/");
    } else {
        $self->assert(-d $path, "dir '$relpath' exists in $dir/");
    }    
}
sub assert_no_path {
    my $self = shift;
    my $relpath = shift;
    my $path = File::Spec->catdir($self->{path}, $relpath);
    my $dir = (File::Spec->splitdir($self->{path}))[-1];
    my (undef, undef, $file) = File::Spec->splitpath($path);

    # make sure errors are reported at the right level
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    if ($file) {
        $self->assert(!-f $path, "no file '$relpath' exists in $dir/");
    } else {
        $self->assert(!-d $path, "no dir '$relpath' exists in $dir/");
    }    
}


sub unchecked_invoke {
    my $self = shift;
    
    my $dir = Cwd::getcwd;
    chdir $self->{path} 
        or die "Couldn't chdir to $self->{path}";
    
    system @_;

    chdir $dir;

    warn "command failed: @_"
        if $?;
}

package MyTest::Replay::CVS;
use strict;
use warnings;
use File::Path qw(mkpath);
use base 'MyTest::Replay';

sub default_executable { 'cvs' }


sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my %param = @_;
    $self->{cvsroot} = $param{cvsroot}
        or die "you must supply a cvsroot parameter"; # FIXME validate?
    ($self->{module}) = $param{module} =~ m!^([\w_.-][\w_.-/]*[\w_.-])$!
        or die "you must supply a valid module parameter";

    my $module_path = File::Spec->catdir($self->{path}, $self->{module});

    $self->playback(<<ACTIONS);
*cvs init
*cvs co .
+$param{module}/
*cvs add $param{module}
*cvs ci -m "created $param{module}"
ACTIONS

    $self->{path} = $module_path; 

    return $self;
}


sub invoke {
    my $self = shift;
    my @command = shift =~ /(\"(?:[^\"]|\\\")*\"|\S+)/g;

    my $name = shift @command;
    die "Invalid command '$name'"
        unless $name eq 'cvs';


    my $exe = $self->{exe_map}{cvs} || 'cvs';

    $self->unchecked_invoke($exe, '-d', $self->{cvsroot}, @command);
}

package MyTest::Replay::Git;
use strict;
use warnings;
use Cwd;
use base 'MyTest::Replay';


sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my %param = @_;
    $self->{cvsroot} = $param{cvsroot};    

# This stops git-cvs from working.  Probably needs to be fixed,
# but it's partly a consequence of the way git-cvsimport works.
#    $self->invoke('git init');

    return $self;
}


sub invoke {
    my $self = shift;
    my @command = shift =~ /(\"(?:[^\"]|\\\")*\"|\S+)/g;

    my $name = shift @command;
    
    die "Invalid command '$name'"
        unless $name =~ /^(git|git-cvs)$/;
    $name = $1;
    
    my $exe = $self->{exe_map}{$name} || $name;

    $self->unchecked_invoke($exe, @command);
}


1;
