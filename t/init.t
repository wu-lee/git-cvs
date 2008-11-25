#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(mkpath rmtree);
use Shell qw(git git-cvs cvs cd);
use Test::More tests => 13;

# This test creates a CVS repo, then git-cvs pulls it somwhere else;
# then tests editing in both git and cvs propagate, and finally,
# branching in cvs propagates to git and changes in the branch
# propagates back again to cvs.

# Note: I've seen problems manifesting as an error message:
# Unknown: error
# These seemed to be due to cvsps caching data in ~/.cvsps - delete that and they go.

# TODO:
# test --author-file

$ENV{PATH} = "$Bin/../bin:$ENV{PATH}";
$Shell::raw = 1;

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

my $test_name = "init";
my $data_dir = "$Bin/data/$test_name";
my $temp_dir = "$Bin/temp/$test_name";
my $cvs_repo = "$temp_dir/cvs";
my $git_work = "$temp_dir/git";
my $cvs_work = "$temp_dir/cvs_template";

rmtree $temp_dir;
ok !-e $temp_dir, "temp dir deleted";
mkpath $temp_dir, $cvs_repo, $git_work;


#mk_cvsrepo $cvs_repo;
cvs '-d', "$cvs_repo", 'init';
ok -d $cvs_repo, "$cvs_repo dir exists";
#ok -d "$cvs_repo/CVS", "$cvs_repo/CVS dir exists";


chdir "$data_dir/cvs_template";
cvs '-d', "$cvs_repo", 'import', '-m', '"initial import"', "cvs_template", 'vendor_tag', 'release_tag';
my $cvs_file_c = "$cvs_repo/cvs_template/c.txt,v";
ok -e $cvs_file_c, "$cvs_file_c exists";

#mk_gitrepo $git_work;
chdir $git_work;

barf "$git_work/.git-cvs", <<CONTENT;
cvsroot=$cvs_repo
cvsmodule=cvs_template
#cvsworking=/home/nick/cvsworking/aspc-pip
CONTENT
ok -f "$git_work/.git-cvs", ".git-cvs file created";

# git --git-dir '/home/nick/svkworking/noofac/trunk/git-cvs/t/temp/init/git/.git' cvsimport -a -p x -v -k -r 'cvs' -o 'cvshead' -d '/home/nick/svkworking/noofac/trunk/git-cvs/t/temp/init/cvs' -C '/home/nick/svkworking/noofac/trunk/git-cvs/t/temp/init/git' 'cvs_template'  > '/home/nick/svkworking/noofac/trunk/git-cvs/t/temp/init/git/2008-11-24-1834-01.cvs-pull.log'
git_cvs 'pull';

ok -f "$git_work/c.txt", "$git_work/c.txt file created";

# hackhack in Git
my $git_file_new1 = "$git_work/new_git";
barf $git_file_new1, "new_git";
git qw(add new_git);
git qw(commit -m), "'added a file'";

git_cvs 'push';
my $cvs_file_new = "$cvs_repo/cvs_template/new_git,v";
ok -f $cvs_file_new, "$cvs_file_new created";

git_cvs 'pull';
git 'reset', '--hard', 'cvs/cvshead';


# check out a cvs working copy
chdir $temp_dir;
cvs '-d', $cvs_repo, 'co', 'cvs_template';
chdir $cvs_work;

# make sure git edit appears
ok -f "$cvs_work/new_git", "$cvs_work/new_git exists";

# hackhack in CVS
my $cvs_work_file_new = "$cvs_work/new_cvs";
barf $cvs_work_file_new, "new";
cvs qw(add new_cvs);
cvs qw(ci -m), "'added another file'";

$cvs_file_new = "$cvs_repo/cvs_template/new_cvs,v";
ok -f $cvs_file_new, "$cvs_file_new created";

# pull the changes back to git
chdir $git_work;
git_cvs 'pull';

ok -f "$git_work/new_cvs", "$git_work/new_cvs file created";

# branch in CVS
chdir $cvs_work;
cvs qw(tag -b BRANCH1);
cvs qw(update -r BRANCH1);
cvs qw(tag BRANCH1_BASE);
cvs qw(tag BRANCH1_LAST_MERGE);
cvs qw(ci -m), "'created BRANCH1'";
my $cvs_work_branch = "$cvs_work/BRANCH1";
barf $cvs_work_branch, "BRANCH1";
cvs qw(add BRANCH1);
cvs qw(ci -m), "'added a branch-identifier file'";

# pull this back to git
chdir $git_work;
git_cvs 'pull';
my $git_file_new2 = "$git_work/BRANCH1";
ok !-f $git_file_new2, "No $git_file_new2 exists in this branch";

# switch to the branch BRANCH1
git qw(checkout cvsworking/BRANCH1);
ok -f $git_file_new2, "$git_file_new2 does exist in this branch";

# hackhack in this branch
git 'rm', 'new_git';
git 'commit', '-m', "'removed new_git'";

# push it back
git_cvs 'push';

# check the file disappears in the cvs working dir
chdir $cvs_work;
$cvs_file_new = "$cvs_work/new_git";
#cvs qw(update -r BRANCH1);
ok -f $cvs_file_new, "$cvs_file_new exists";
cvs qw(update -d);
ok !-f $cvs_file_new, "$cvs_file_new deleted";
