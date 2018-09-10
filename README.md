# pcdm-manifests

Implementation of the [IIIF Presentation API](http://iiif.io/api/presentation/2.1/)
that generates IIIF Manifests from [PCDM](https://pcdm.org/) objects in a Fedora 
repository.

## Quick Start

Requires Ruby v2.2.4

```
git clone git@github.com:umd-lib/pcdm-manifests.git
cd pcdm-manifests

gem install bundler
bundle install
rails server
```

JSON manifests of an issue can be obtained by making a HTTP get request in the following format.

```
curl http://localhost:3000/manifests/IIIF_ID/manifest
```

The general structure of the `IIIF_ID` is `prefix:id`. The exact format of the `id` varies by handler.

## Handlers

### fcrepo

* **Prefix:** `fcrepo`
* **ID:** The URL_encoded repository path to the resource (part of the PCDM resource URI after the Fedora base URI). There is also a shorthand that uses `::` to indicate the presence of a 4-element pairtree before a UUID.

#### Example

|                   |Value|
|-------------------|-----|
|**Fedora URI**     |https://fcrepolocal/fcrepo/rest/pcdm/ab/b4/b3/04/abb4b304-5e96-478f-8abb-8c5aafd42223|
|**Fedora Base URI**|https://fcrepolocal/fcrepo/rest/|
|**IIIF ID**        |fcrepo:pcdm%2Fab%2Fb4%2Fb3%2F04%2Fabb4b304-5e96-478f-8abb-8c5aafd42223<br>*OR*<br>fcrepo:pcdm::abb4b304-5e96-478f-8abb-8c5aafd42223|
|**Manifest URI**   |http://localhost:3000/manifests/fcrepo:ab%2Fb4%2Fb3%2F04%2Fabb4b304-5e96-478f-8abb-8c5aafd42223/manifest<br>*OR*<br>http://localhost:3000/manifests/fcrepo:pcdm::abb4b304-5e96-478f-8abb-8c5aafd42223/manifest|

### fedora2

* **Prefix:** `fedora2`
* **ID:** The `umd:` PID of the resource.

## Configuration

The following environment variables are used to configure the services
used by PCDM Manifests in production:

|Variable           |Purpose|
|-------------------|-------|
|`SOLR_URL`         |URL of the Solr core to query; this core must have a `pcdm` request handler|
|`FCREPO_URL`       |Base URL of the Fedora repository|
|`FEDORA2_URL`      |Base URL of the Fedora 2 repository|
|`FEDORA2_SOLR_URL` |URL of the Solr core to query for the Fedora 2 metadata|
|`IIIF_IMAGE_URL`   |Base URL for the IIIF Image API service|
|`IIIF_MANIFEST_URL`|Base URL for this service|

See [config/iiif.yml](config/iiif.yml) for examples.

## License

See the [LICENSE](LICENSE.md) file for license rights and limitations (Apache 2.0).

