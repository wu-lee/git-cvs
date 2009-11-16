#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use MyTest::Dirs;
use MyTest::Replay;

use Test::More tests => 2;

# This tests pushing twice without pulling in between
# Currently it fails!  

# Define some directories
my %D = MyTest::Dirs->hash(
    data => [],
    temp => [cvs_repo => 'cvs',
             cvs_work => 'cvs_work',
             git_repo => 'git'],
);

my $cvs_module = 'module1';

# Create a cvs repo and working dir
my $cvs = MyTest::Replay::CVS->new(path => $D{cvs_work},
                                   module => $cvs_module,
                                   cvsroot => $D{cvs_repo});

$cvs->playback(<<ACTIONS);
## Check in a couple of files
+one
+two 
*cvs add one two
*cvs ci -m "added one and two"
ACTIONS

# Create a git repo, which explicitly uses our dist's git cvs
my $git = MyTest::Replay::Git->new(path => $D{git_repo},
                                   exe_map => {
                                       'git-cvs' => "$Bin/../bin/git-cvs",
                                   });


$git->playback(<<ACTIONS);
## Init .git-cvs and make the first import from CVS
+.git-cvs cvsroot=$D{cvs_repo}
+.git-cvs cvsmodule=$cvs_module

*git-cvs pull
?one
?two
ACTIONS

$git->playback(<<ACTIONS);
## Now add a file in git
+alpha
*git add alpha
*git commit -m "added alpha" 

*git-cvs push
ACTIONS

$git->playback(<<ACTIONS);
+beta
*git add beta
*git commit -m "added beta" 

*git-cvs push
ACTIONS

__END__
Firstly, thank you and congratulations on being the first self-confessed user of git-cvs!  I wasn't aware of anyone else using it so far.

Now, to try and help you - something more specific would help me replicate your problem.  I'm guessing you're doing something like this?

$ mkdir repo_name
$ cd repo_name
$ echo cvsroot=$CVS_ROOT      >.git-cvs
$ echo cvsmodule=$CVS_MODULE >>.git-cvs
$ git-cvs pull
$ echo hello > foo
$ git commit -a -m "comitted foo"
$ git-cvs push
$ echo hello again >>foo
$ git commit -a -m "comitted foo again"
$ git-cvs push # some error here?

I've created a unit test which tries to replicate this, called t/von-1.t.  You might want to check this does indeed replicate your problem (I've checked it in).

What I think you have found here is a "misfeature", which I personally avoid by git-pulling after each push (followed by a git reset --hard master to remove the merge point).  This keeps the git repo's master branch  in sync with the CVS repo HEAD branch (assumng you're on master).

I did experiment with recording the last push with a tag, but shelved this idea, I think because correctly deducing the right commits to export in all circumstances seemed hard to get right.

I'll think a bit more about tomorrow, when it might all seem much simpler.  I need sleep right now...
