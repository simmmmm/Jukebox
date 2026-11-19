# What dev/linux-build.sh builds Jukebox for Linux in: Swift's own image
# (the same one dev/kit-test.sh tests the kit in) with GTK 4, libadwaita 1.5,
# GStreamer, libsecret's and libsoup's headers. Ubuntu 24.04's versions are the floor:
# a binary linked here runs on anything newer.
FROM swift:6.2-noble
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgtk-4-dev libadwaita-1-dev libgstreamer1.0-dev libsecret-1-dev libsoup-3.0-dev \
    && rm -rf /var/lib/apt/lists/*
