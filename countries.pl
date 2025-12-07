#! /usr/bin/env perl

use v5.24;
use warnings;

use Archive::SCS::GameDir ();
use Data::SCS::DefParser ();
use Getopt::Long qw( GetOptions :config gnu_getopt );
use List::Util qw( any first );
use Pod::Usage qw( pod2usage );
use Text::CSV qw( csv );
use YAML::Tiny ();

my %opts = (
  game => 'ATS',
);
pod2usage unless GetOptions \%opts, qw(
  game|g=s
  help|?
);
pod2usage -verbose => 2 if $opts{help};


# Create static YAML game data dump

my $version = Archive::SCS::GameDir->new( game => $opts{game} )->version;
my $data    = Data::SCS::DefParser->new( mount => $opts{game} )->data;
my @countries;

for my $branch_token ( sort keys $data->{company}{permanent}->%* ) {
  push $data->{city}{ $_->{city} }{branches}->@*, $branch_token
    for $data->{company}{permanent}{ $branch_token }{company_def}->@*;
}

for my $city_token ( sort keys $data->{city}->%* ) {
  my $country_token = $data->{city}{ $city_token }{country};
  push $data->{country}{data}{ $country_token }{cities}->@*, $city_token;
}

for my $country_token ( sort keys $data->{country}{data}->%* ) {
  my $country = $data->{country}{data}{ $country_token };
  my @cities = grep { $data->{city}{ $_ }{branches} } $country->{cities}->@*
    or next;

  push @countries, {
    token  => $country_token,
    code   => uc $country->{iso_country_code} =~ s/^(ca|us)(\w\w)/$1-$2/air,
    name   => $country->{name},
    cities => [ map {+{
      token     => $_,
      name      => $data->{city}{ $_ }{city_name},
      locations => scalar $data->{city}{ $_ }{branches}->@*,
    }} @cities ],
  };
}

YAML::Tiny->new( \@countries, $version )->write('countries.yml');


# Verify against expected city count

my $countries_table = csv
  headers => 'auto',
  in      => 'countries.csv';

for my $row ( $countries_table->@* ) {
  my $country = first { $_->{code} eq $row->{country} } @countries;
  if ($country) {
    $country->{expected} = $row->{cities};
    $country->{cities}->@* == $country->{expected} or die
      sprintf "Expected %i cities for %s, found %i",
      $row->{cities}, $country->{name}, (scalar $country->{cities}->@*);
  }
}

for my $country ( grep { ! defined $_->{expected} } @countries ) {
  # Country isn't yet in table with expected city counts, so let's add it
  push $countries_table->@*, {
    country => $country->{code},
    name    => $country->{name},
    cities  => (scalar $country->{cities}->@*),
  };
}

csv
  quote_space => 0,
  headers => [qw( country name cities )],
  in      => [ sort { $a->{name} cmp $b->{name} } $countries_table->@* ],
  out     => 'countries.csv';


__END__

=head1 SYNOPSIS

  countries.pl
  countries.pl --help

=head1 DESCRIPTION

Create the static F<countries.yml> dataset in the current work
directory from a local game installation. Will overwrite an
existing file.

The city count is checked against the F<countries.csv> table.
Countries (states/provinces) in the game that aren't yet present
in this table will be added to it.

=head1 OPTIONS

=over

=item --game, -g

The game name or game directory to mount. Defaults to C<ATS>.
See L<Archive::SCS::GameDir>.

=item --help, -?

Display this manual page.

=back
