package Mojolicious::Command::test;
use Mojo::Base 'Mojolicious::Command';

use Cwd 'realpath';
use FindBin;
use File::Spec::Functions qw(abs2rel catdir splitdir);
use Mojo::Home;

has description => "Run unit tests.\n";
has usage       => <<"EOF";
usage: $0 test [OPTIONS] [TESTS]

These options are available:
  -v, --verbose   Print verbose debug information to STDERR.
EOF

# "Why, the secret ingredient was...water!
#  Yes, ordinary water, laced with nothing more than a few spoonfuls of LSD."
sub run {
  my ($self, @args) = @_;

  # Options
  $self->_options(\@args, 'v|verbose' => sub { $ENV{HARNESS_VERBOSE} = 1 });

  # Search tests
  unless (@args) {
    my @base = splitdir(abs2rel $FindBin::Bin);

    # Test directory in the same directory as "mojo" (t)
    my $path = catdir @base, 't';

    # Test dirctory in the directory above "mojo" (../t)
    $path = catdir @base, '..', 't' unless -d $path;
    die "Can't find test directory.\n" unless -d $path;

    # List test files
    my $home = Mojo::Home->new($path);
    /\.t$/ and push(@args, $home->rel_file($_)) for @{$home->list_files};

    say "Running tests from '", realpath($path), "'.";
  }

  # Run tests
  $ENV{HARNESS_OPTIONS} //= 'c';
  require Test::Harness;
  Test::Harness::runtests(sort @args);
}

1;

=head1 NAME

Mojolicious::Command::test - Test command

=head1 SYNOPSIS

  use Mojolicious::Command::test;

  my $test = Mojolicious::Command::test->new;
  $test->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::test> runs application tests from the C<t> directory.

=head1 ATTRIBUTES

L<Mojolicious::Command::test> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 C<description>

  my $description = $test->description;
  $test           = $test->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $test->usage;
  $test     = $test->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::test> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 C<run>

  $test->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
