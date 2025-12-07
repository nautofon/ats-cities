#! /usr/bin/env perl

use v5.24;
use warnings;

use HTTP::Tiny;
use JSON::MaybeXS;
use List::Util 'first';
use Path::Tiny;
use Text::CSV 'csv';
use Text::Table::HTML;
use Time::Piece;
use YAML::Tiny;

my $url = 'https://truckermudgeon.github.io/extra-labels.geojson';
my $dir = path 'pages';


# Use the static YAML and CSV files as primary data source

my %countries;
$countries{ $_->{code} } = $_ for YAML::Tiny->read('countries.yml')->[0]->@*;

my $countries_table = csv
  headers => 'auto',
  in      => 'countries.csv';

for my $row ( $countries_table->@* ) {
  my $country = ($countries{ $row->{country} } //= {});
  $country->{code}     = $row->{country};
  $country->{name}     = $row->{name};
  $country->{expected} = $row->{cities};
}


# Augment YAML game data dump with GeoJSON map labels
# (the GeoJSON may include more cities, but is more fragile overall)

my $response = HTTP::Tiny->new->get($url);
$response->{success} or die "$url: $response->{status} $response->{reason}";
my $json = decode_json $response->{content};

# Temp fix: Add cities currently missing from extra-labels dataset
$json->{features} = [ grep {
  ($_->{properties}{text} // '') ne 'Saint Joseph'
} $json->{features}->@* ];
push $json->{features}->@*,
  map {+{ properties => { kind => 'city', $_->%* } }} (
    { country => 'US-MO', text => 'Saint Joseph', city => 'st_joseph' },
    { country => 'US-MO', text => 'Saint Louis',  city => 'st_louis' },
  );

for my $feature ( $json->{features}->@* ) {
  no warnings 'uninitialized';
  my $meta = $feature->{properties};
  next unless $meta->{country} && $meta->{kind} eq 'city';

  my $country = ($countries{ $meta->{country} } //= {
    cities => [],
    code   => $meta->{country},
  });
  my $city = defined $meta->{city} &&
    first { $meta->{city} eq $_->{token} } $country->{cities}->@*;

  push $country->{cities}->@*, {
    token => $meta->{city},
    name  => $meta->{text},
  } unless $city;
}


# Write output files

my @cities;
for my $country_code ( sort keys %countries ) {
  my $country_cities = $countries{ $country_code }{cities};
  $country_cities->@* = sort { $a->{name} cmp $b->{name} } $country_cities->@*;

  push @cities, map {+{
    country => $country_code,
    city    => $_->{name},
    token   => $_->{token},
  }} $country_cities->@*;
}

$dir->mkdir;
$dir->child('ats-cities.json')->spew_raw(encode_json \@cities);

my $header = [qw( country city token )];
my @table = map {[
  $_->{country},
  $_->{city},
  $_->{token},
]} @cities;
csv in => [$header, @table], out => "$dir/ats-cities.csv";

# Get human-readable country/state names for HTML output
$_->[0] = $countries{ $_->[0] }{name} for @table;
@table = sort { $a->[0] cmp $b->[0] } @table;
$header = ['State', 'City', 'Game Token'];

# Verify that the city count for each country/state is as expected
for my $country ( sort keys %countries ) {
  my $listed_cities   = grep { $_->{country} eq $country } @cities;
  my $expected_cities = $countries{$country}{expected};
  if ( $listed_cities != $expected_cities ) {
    warn sprintf "Expected %i cities for %s, found %i",
      $expected_cities, $country, $listed_cities;
  }
}

$dir->child('index.html')->spew_utf8(
  path('table.html')->slurp_utf8,
  sprintf("<p class=updated>Last updated: %s\n\n", gmtime->strftime),
  Text::Table::HTML::table(
    rows => [$header, @table],
    header_row => 1,
  ),
);


__END__

=head1 SYNOPSIS

  pages.pl

=head1 DESCRIPTION

Create the C<pages> directory containing the output files.
Existing files will be overwritten.
