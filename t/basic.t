#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use MyTest qw(barf git_cvs);
use MyTest::Dirs;
use MyTest::Replay;

use File::Path qw(mkpath rmtree);
use Shell qw(git cvs cd);
use Test::More tests => 16;

# This tests basic usage


$ENV{PATH} = "$Bin/../bin:$ENV{PATH}";
$Shell::raw = 1;

my %D = MyTest::Dirs->hash(
    data => [],
    temp => [cvs_repo => 'cvs',
             cvs_work => 'cvs_work',
             git_repo => 'git'],
);

my $cvs_module = 'module1';

# create a cvs repo and working dir
my $cvs = MyTest::Replay::CVS->new(path => $D{cvs_work},
                                   module => $cvs_module,
                                   cvsroot => $D{cvs_repo});

$cvs->playback(<<ACTIONS);
# check in a couple of files
+one
+two 
*cvs add one two
*cvs ci -m "added one and two"
ACTIONS

# create a git repo
my $git = MyTest::Replay::Git->new(path => $D{git_repo});

$git->playback(<<ACTIONS);
# init .git-cvs and make the first import from CVS
+.git-cvs cvsroot=$D{cvs_repo}
+.git-cvs cvsmodule=$cvs_module
*git-cvs pull
?one
?two

# now add a file in git
+three
*git add three
*git commit -m "added three" 
*git-cvs push
*git-cvs pull
*git reset --hard cvs/cvshead
ACTIONS

$cvs->playback(<<ACTIONS);
# pull that back to CVS
*cvs up -d
?three

# add a new file in CVS
+four
*cvs add four
*cvs ci -m "added four"
ACTIONS

$git->playback(<<ACTIONS);
# pull back a second time from CVS
*git-cvs pull
*git reset --hard cvs/cvshead
?one
?two
?three
?four
ACTIONS

$cvs->playback(<<ACTIONS);
# branch in CVS
*cvs tag -b BRANCH1
*cvs update -r BRANCH1
*cvs tag BRANCH1_BASE
*cvs tag BRANCH1_LAST_MERGE
*cvs ci -m "created BRANCH1"

# create a file to identify that branch
+cvs_branch1
*cvs add cvs_branch1
*cvs ci -m "added file cvs_branch1"
ACTIONS


# can we see the branches?

$git->playback(<<ACTIONS);
# pull the changes back to git
*git-cvs pull

# can we see the remote branches?
?.git/refs/remotes/cvs/cvshead
?.git/refs/remotes/cvs/HEAD
?.git/refs/remotes/cvs/BRANCH1

# and the tracking branch?
?.git/refs/heads/cvsworking/BRANCH1

# but is the branch1 absent?
!cvs_branch1

# now switch to BRANCH1 
*git checkout cvsworking/BRANCH1
*git reset --hard cvs/BRANCH1
?cvs_branch1

# and modify it
+git/branch1 hello
*git add git/branch1
*git commit -m "added git/branch1"

# push it back
*git-cvs push
ACTIONS


$cvs->playback(<<ACTIONS);
# check the changes appear in CVS
*cvs up -d
?git/branch1?
ACTIONS



# This test aims to test the problem I experienced where a 
# file added in one branch block it being added in another.

$git->playback(<<ACTIONS);
# pull last changes back into git
*git-cvs pull
*git reset --hard cvs/BRANCH1
ACTIONS


$cvs->playback(<<ACTIONS);
# add a file in HEAD
*cvs up -d -A
+cvs_nasty
*cvs add cvs_nasty
*cvs ci -m "added cvs_nasty in cvs HEAD"
ACTIONS

$git->playback(<<ACTIONS);
# now add another with the same name in BRANCH1
#*git checkout BRANCH1
+cvs_nasty
*git add cvs_nasty
*git commit -m "added cvs_nasty in Git BRANCH1"
ACTIONS


# PUSH:
# Checking if patch will apply
# U cvs_nasty
# Huh? Status reported for unexpected file 'cvs_nasty'
# Applying
# error: cvs_nasty: already exists in working directory
# cannot patch at /usr/bin/git-cvsexportcommit line 282.


#  PULL:
# Running cvsps...
# cvs_direct initialized to CVSROOT /home/nick/svkworking/noofac/trunk/git-cvs/t/temp/basic/cvs
# cvs rlog: Logging module1
# cvs rlog: Logging module1/git
# WARNING: branch_add already set!
# skip patchset 1: 1227900176 before 1227900182
# skip patchset 2: 1227900179 before 1227900182
# skip patchset 3: 1227900182 before 1227900182
# skip patchset 4: 1227900184 before 1227900187
# skip patchset 5: 1227900187 before 1227900187
# Fetching cvs_nasty   v 1.1.2.1
# Update cvs_nasty: 1 bytes
# Tree ID f4f6d39d1bf27228774ada9855166726a3932919
# Parent ID 9fe53101457f4b08af7c456255b68458e55beb39
# Committed patch 6 (BRANCH1 +0000 2008-11-28 19:23:10)
# Commit ID e2714f3aae88d4bbcb554ba692e8789a6bb41498
# DONE.
# Already up-to-date.
# invoking: git --git-dir '/home/nick/svkworking/noofac/trunk/git-cvs/t/temp/basic/git/.git' show-ref


$git->playback(<<ACTIONS);
# and push to cvs
*git-cvs push

# pull the changes back to git
*git-cvs pull

# is it ok?
?cvs_nasty
*git checkout cvsworking/BRANCH1
?cvs_nasty
ACTIONS
