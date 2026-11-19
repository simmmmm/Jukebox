#!/usr/bin/env python3
# A fake Sonos on 127.0.0.1, for Play On's UPnP side without a speaker in
# the house (Linux/App/UPnP.swift). It describes itself as a Sonos room,
# says its topology (two rooms playing together, a bonded surround that is
# no row), and keeps an AVTransport's state as a Sonos does: a song plays
# for its DIDL duration (at most FAKE_SECONDS, 6 by default) and then the
# transport is STOPPED. Every action is printed, so a test reads what the
# app said.
#
#   dev/fake-upnp-renderer.py 1400
#   JUKEBOX_UPNP_DEVICE=http://127.0.0.1:1400/xml/device_description.xml \
#     JUKEBOX_CHECK=upnp .build-linux/debug/Jukebox
import html
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 1400
BASE = f"http://127.0.0.1:{PORT}"
LIMIT = float(os.environ.get("FAKE_SECONDS", "6"))

DESCRIPTION = f"""<?xml version="1.0" encoding="utf-8" ?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><device>
<deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
<friendlyName>127.0.0.1 - Sonos One - RINCON_FAKE01400</friendlyName>
<manufacturer>Sonos, Inc.</manufacturer><modelName>Sonos One</modelName>
<UDN>uuid:RINCON_FAKE01400</UDN><roomName>Fake Room</roomName>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:ZoneGroupTopology:1</serviceType>
<controlURL>/ZoneGroupTopology/Control</controlURL></service></serviceList>
<deviceList><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<UDN>uuid:RINCON_FAKE01400_MR</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
<controlURL>/MediaRenderer/RenderingControl/Control</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>/MediaRenderer/AVTransport/Control</controlURL></service>
</serviceList></device></deviceList></device></root>"""

# The same transport as a plain DLNA renderer, for SSDP_ANSWER.
RENDERER = f"""<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><device>
<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>Fake Speaker</friendlyName><manufacturer>Jukebox</manufacturer><modelName>Fake Renderer</modelName>
<UDN>uuid:fake-renderer-1</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
<controlURL>/MediaRenderer/RenderingControl/Control</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>/MediaRenderer/AVTransport/Control</controlURL></service>
</serviceList></device></root>"""

TOPOLOGY = f"""<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_FAKE01400" ID="RINCON_FAKE01400:1">
<ZoneGroupMember UUID="RINCON_FAKE01400" Location="{BASE}/xml/device_description.xml" ZoneName="Fake Room">
<Satellite UUID="RINCON_SUB01400" Location="{BASE}/xml/device_description.xml" ZoneName="Fake Room" Invisible="1"/>
</ZoneGroupMember>
<ZoneGroupMember UUID="RINCON_KITCHEN01400" Location="{BASE}/xml/device_description.xml" ZoneName="Fake Kitchen"/>
<ZoneGroupMember UUID="RINCON_SURROUND01400" Location="{BASE}/xml/device_description.xml" ZoneName="Fake Room" Invisible="1"/>
</ZoneGroup></ZoneGroups><VanishedDevices></VanishedDevices></ZoneGroupState>"""

state = {"transport": "NO_MEDIA_PRESENT", "uri": "", "length": LIMIT, "at": 0.0, "since": None, "volume": 20}


def position():
    at = state["at"]
    if state["since"] is not None:
        at += time.time() - state["since"]
    if at >= state["length"] and state["transport"] == "PLAYING":
        # The song is over: stopped, at the start, as a Sonos is.
        state.update(transport="STOPPED", at=0.0, since=None)
        print("fake: ended", flush=True)
        return 0.0
    return at


def hms(seconds):
    whole = int(seconds)
    return f"{whole // 3600}:{whole // 60 % 60:02d}:{whole % 60:02d}"


def argument(body, name):
    found = re.search(rf"<{name}>(.*?)</{name}>", body, re.S)
    return html.unescape(found.group(1)) if found else ""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, text):
        data = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", 'text/xml; charset="utf-8"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/xml/device_description.xml":
            self.send(200, DESCRIPTION)
        elif self.path == "/xml/renderer.xml":
            self.send(200, RENDERER)
        else:
            self.send(404, "")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        soap = self.headers.get("SOAPACTION", "").strip('"')
        service, _, action = soap.partition("#")
        values = {}
        position()
        if action == "GetZoneGroupState":
            values["ZoneGroupState"] = TOPOLOGY
        elif action == "SetAVTransportURI":
            state["uri"] = argument(body, "CurrentURI")
            metadata = argument(body, "CurrentURIMetaData")
            length = re.search(r'duration="([0-9:.]+)"', metadata)
            seconds = LIMIT
            if length:
                h, m, s = length.group(1).split(":")
                seconds = min(LIMIT, int(h) * 3600 + int(m) * 60 + float(s))
            state.update(transport="STOPPED", length=seconds, at=0.0, since=None)
            title = re.search(r"<dc:title>(.*?)</dc:title>", metadata)
            print(f"fake: SetAVTransportURI {state['uri']} title={html.unescape(title.group(1)) if title else None}", flush=True)
        elif action == "Play":
            state.update(transport="PLAYING", since=time.time())
        elif action == "Pause":
            state.update(transport="PAUSED_PLAYBACK", at=position(), since=None)
        elif action == "Stop":
            state.update(transport="STOPPED", at=0.0, since=None)
        elif action == "Seek":
            target = argument(body, "Target")
            h, m, s = target.split(":")
            playing = state["transport"] == "PLAYING"
            state.update(at=int(h) * 3600 + int(m) * 60 + float(s), since=time.time() if playing else None)
        elif action == "GetTransportInfo":
            values = {"CurrentTransportState": state["transport"], "CurrentTransportStatus": "OK", "CurrentSpeed": "1"}
        elif action == "GetPositionInfo":
            values = {"Track": "1", "TrackDuration": hms(state["length"]), "TrackURI": state["uri"],
                      "RelTime": hms(position()), "AbsTime": "NOT_IMPLEMENTED"}
        elif action == "GetVolume":
            values = {"CurrentVolume": str(state["volume"])}
        elif action == "SetVolume":
            state["volume"] = int(argument(body, "DesiredVolume"))
        else:
            self.send(500, "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault>"
                           "<faultstring>UPnPError</faultstring><detail><UPnPError><errorCode>401</errorCode>"
                           "</UPnPError></detail></s:Fault></s:Body></s:Envelope>")
            return
        if not action.startswith("Get"):
            print(f"fake: {action} -> {state['transport']} at {position():.1f} volume {state['volume']}", flush=True)
        inner = "".join(f"<{k}>{html.escape(v, quote=False)}</{k}>" for k, v in values.items())
        self.send(200, '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                       f'<u:{action}Response xmlns:u="{service}">{inner}</u:{action}Response></s:Body></s:Envelope>')


def answer_searches():
    """SSDP_ANSWER=1: answers every MediaRenderer M-SEARCH on this machine's
    own multicast loop with the plain renderer, so the app's SSDP is heard
    (from the machine itself, which a host firewall lets through)."""
    import socket
    import struct
    listen = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    listen.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listen.bind(("", 1900))
    listen.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                      struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton("0.0.0.0")))
    while True:
        data, sender = listen.recvfrom(4096)
        text = data.decode(errors="replace")
        if text.startswith("M-SEARCH") and "MediaRenderer" in text:
            print(f"fake: M-SEARCH from {sender[0]}:{sender[1]}", flush=True)
            listen.sendto((f"HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: {BASE}/xml/renderer.xml\r\n"
                           "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:fake-renderer-1::"
                           "urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n").encode(), sender)


if os.environ.get("SSDP_ANSWER"):
    import threading
    threading.Thread(target=answer_searches, daemon=True).start()
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
