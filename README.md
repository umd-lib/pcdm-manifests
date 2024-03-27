# pcdm-manifests

Implementation of the [IIIF Presentation
API](http://iiif.io/api/presentation/2.1/) that generates IIIF Manifests from
[PCDM](https://pcdm.org/) objects in a Fedora repository.

## Quick Start

Requires Ruby v3.0.6

```zsh
git clone git@github.com:umd-lib/pcdm-manifests.git
cd pcdm-manifests

gem install bundler
bundle install
rails server
```

JSON manifests of an issue can be obtained by making an HTTP GET request in the
following format.

```zsh
curl http://localhost:3000/manifests/IIIF_ID/manifest
```

The general structure of the `IIIF_ID` is `prefix:id`. The exact format of the
`id` varies by handler.

## Handlers

### fcrepo

* **Prefix:** `fcrepo`
* **ID:** The URL_encoded repository path to the resource (part of the PCDM
  resource URI after the Fedora base URI). There is also a shorthand that uses
  `::` to indicate the presence of a 4-element pairtree before a UUID.

#### Example

|                   |Value|
|-------------------|-----|
|**Fedora URI**     |<https://fcrepolocal/fcrepo/rest/pcdm/ab/b4/b3/04/abb4b304-5e96-478f-8abb-8c5aafd42223>|
|**Fedora Base URI**|<https://fcrepolocal/fcrepo/rest/>|
|**IIIF ID**        |fcrepo:pcdm%2Fab%2Fb4%2Fb3%2F04%2Fabb4b304-5e96-478f-8abb-8c5aafd42223<br>*OR*<br>fcrepo:pcdm::abb4b304-5e96-478f-8abb-8c5aafd42223|
|**Manifest URI**   |<http://localhost:3000/manifests/fcrepo:ab%2Fb4%2Fb3%2F04%2Fabb4b304-5e96-478f-8abb-8c5aafd42223/manifest><br>*OR*<br><http://localhost:3000/manifests/fcrepo:pcdm::abb4b304-5e96-478f-8abb-8c5aafd42223/manifest>|

### fedora2

* **Prefix:** `fedora2`
* **ID:** The `umd:` PID of the resource.

## Configuration

The following environment variables are used to configure the services used by
PCDM Manifests in production:

|Variable           |Purpose|
|-------------------|-------|
|`SOLR_URL`         |URL of the Solr core to query; this core must have a `pcdm` request handler|
|`FCREPO_URL`       |Base URL of the Fedora repository|
|`FEDORA2_URL`      |Base URL of the Fedora 2 repository|
|`FEDORA2_SOLR_URL` |URL of the Solr core to query for the Fedora 2 metadata|
|`FCREPO_SOLR_URL`  |Should be set to the same as `SOLR_URL`|
|`IIIF_IMAGE_URL`   |Base URL for the IIIF Image API service|
|`IIIF_MANIFEST_URL`|Base URL for this service|

See [config/iiif.yml](config/iiif.yml) for examples.

## Docker

This repository contains a [Dockerfile](Dockerfile) for building a deployable
image of this application:

```zsh
# build an image tagged with the current application version
VERSION="$(rails app:version)" .
docker build -t "pcdm-manifests:$VERSION" .

# build an image tagged with the current application version, plus the current
# git commit hash (useful for development builds)
VERSION="$(rails app:version)-$(git rev-parse --short=8 HEAD)" .
docker build -t "pcdm-manifests:$VERSION" .
```

To run the image, bind port 3000 to 3000 on localhost:

```zsh
docker run -it --rm -p 3000:3000 -e RAILS_ENV='development' "pcdm-manifests:$VERSION"
```

There should be a simple splash page at <http://localhost:3000/>

## Building the Docker Image for K8s Deployment

The following procedure uses the Docker "buildx" functionality and the
Kubernetes "build" namespace to build the Docker image. This procedure should
work on both "arm64" and "amd64" MacBooks.

The image will be automatically pushed to the Nexus.

### Local Machine Setup

See <https://github.com/umd-lib/k8s/blob/main/docs/DockerBuilds.md> in
GitHub for information about setting up a MacBook to use the Kubernetes
"build" namespace.

### Creating the Docker image

1. In an empty directory, checkout the Git repository and switch into the
   directory:

    ```zsh
    $ git clone git@github.com:umd-lib/pcdm-manifests.git
    $ cd pcdm-manifests
    ```

2. Checkout the appropriate Git tag, branch, or commit for the Docker image.

3. Set up an "APP_TAG" environment variable:

    ```zsh
    $ export APP_TAG=<DOCKER_IMAGE_TAG>
    ```

   where \<DOCKER_IMAGE_TAG> is the Docker image tag to associate with the
   Docker image. This will typically be the Git tag for the application version,
   or some other identifier, such as a Git commit hash. For example, using the
   Git tag of "1.2.0":

    ```zsh
    $ export APP_TAG=1.2.0
    ```

    Alternatively, to use the Git branch and commit:

    ```zsh
    $ export GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
    $ export GIT_COMMIT_HASH=`git rev-parse HEAD`
    $ export APP_TAG=${GIT_BRANCH}-${GIT_COMMIT_HASH}
    ```

4. Switch to the Kubernetes "build" namespace:

    ```bash
    $ kubectl config use-context build
    ```

5. Create the "docker.lib.umd.edu/pcdm-manifests" Docker image:

    ```bash
    $ docker buildx build --no-cache --platform linux/amd64 --push --no-cache \
        --builder=kube  -f Dockerfile -t docker.lib.umd.edu/pcdm-manifests:$APP_TAG .
    ```

   The Docker image will be automatically pushed to the Nexus.

## License

See the [LICENSE](LICENSE.md) file for license rights and limitations (Apache
2.0).
