Expects a secret named `nzbget-creds`, with key `password`

# Supporting services

Ombi, Sonarr, Radarr, and NzbGet do nothing in isolation - you need to hook them up to supporting services to access any data.

## Indexers

These are the services that translate search requests into sets of Usenet post addresses to be downloaded and collated.

I currently use:

* NzbPlanet
* NZBGeek

And have been advised to try:

* DrunkenSlug
* Nzb.su
* NZBFinder

## Providers

These are the services that host the actual data

I use:

* Usenetserver

And have been advised to try:

* usenet.farm

# See also

The `gluetun-vpn` chart
