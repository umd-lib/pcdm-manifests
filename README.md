# pcdm-manifests

Utility to generate IIIF Manifests from PCDM objects and deliver them through a web interface.

## Quick Start

Requires Ruby v2.2.4

```
git clone git@github.com:umd-lib/pcdm-manifests.git
cd pcdm-manifests

gem install bundler
bundle install
rails server
```

Json manifests of an issue can be obtained by making a HTTP get request in the following format.

```
curl http://localhost:3000/manifests/<ENCODED_PCDM_RESOURCE_RELATIVE_PATH>
```

Where `ENCODED_PCDM_RESOURCE_RELATIVE_PATH` should be:

* the part of the pcdm resource uri after the `fcrepo_base_uri`.
* url encoded (to replace `/` by `%2F`).
* the path of an issue, or a page or file related to the issue.

For example, given the URI of an issue/page/file in fcrepo:

```
https://fcrepolocal/fcrepo/rest/pcdm/ab/b4/b3/04/abb4b304-5e96-478f-8abb-8c5aafd42223
```

The manifest URI will be:

```
http://localhost:3000/manifests/ab%2Fb4%2Fb3%2F04%2Fabb4b304-5e96-478f-8abb-8c5aafd42223
```

## Configuration

The `config/pcdm2manifest.yml` file has the configuration option necessary for the generation of the manifests from a fedora resource id.

```
# Provide the path the https certificate of the fcrepo server.
# REQUIRED if the fcrepo server has a self signed certificate.
server_cert: fcrepolocal.pem

# Authentication information for fcrepo
username: tester 
password: tester

# Fcrepo PCDM container URI
fcrepo_base_uri: https://fcrepolocal/fcrepo/rest/pcdm/

# IIIF Image Server Base URI
iiif_image_uri: https://iiiflocal/images/

# IIIF Manifests Server Base URI
iiif_manifest_uri: https://iiiflocal/manifests/
```

### Using the pcdm2manifest.rb script from command line:
The `pcdm2manifest.rb` can also be used from the command line to generate the manifest of a given fcrepo pcdm resource. The script has to be run from the root directory of the project for the configuration files to be accessible. 

Syntax:

```
app/controllers/concerns/pcdm2manifest.rb <FCREPO_RESOURCE_URI>
```

Example:

```
app/controllers/concerns/pcdm2manifest.rb https://fcrepolocal/fcrepo/rest/pcdm/ab/b4/b3/04/abb4b304-5e96-478f-8abb-8c5aafd42223
```

