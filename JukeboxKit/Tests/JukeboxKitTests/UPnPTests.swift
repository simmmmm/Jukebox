// UPnP AV for a Sonos and other renderers (Cast/UPnP.swift): what is sent
// and what is read, without a device. The answers are a real Sonos One SL's
// (S2, 19 November 2026), shortened; Linux's JUKEBOX_CHECK=upnp plays
// against a fake renderer (dev/fake-upnp-renderer.py).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite struct UPnPTests {
    @Test func searchesForATarget() {
        let message = SSDP.search(SSDP.zonePlayer)
        #expect(message.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        #expect(message.contains("HOST: 239.255.255.250:1900\r\n"))
        #expect(message.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(message.contains("ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"))
        #expect(message.hasSuffix("\r\n\r\n"))
    }

    @Test func readsAnAnswer() throws {
        let answer = try #require(SSDP.parse("""
            HTTP/1.1 200 OK\r
            CACHE-CONTROL: max-age = 1800\r
            EXT:\r
            location: http://192.168.2.8:1400/xml/device_description.xml\r
            SERVER: Linux UPnP/1.0 Sonos/98.0-82170 (ZPS38)\r
            ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
            USN: uuid:RINCON_38420B7E66AA01400::urn:schemas-upnp-org:device:ZonePlayer:1\r
            \r

            """))
        #expect(answer.location == URL(string: "http://192.168.2.8:1400/xml/device_description.xml"))
        #expect(answer.target == SSDP.zonePlayer)
        #expect(answer.usn.hasPrefix("uuid:RINCON_38420B7E66AA01400"))
    }

    @Test func ignoresWhatIsNoAnswer() {
        #expect(SSDP.parse("M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n\r\n") == nil)
        #expect(SSDP.parse("NOTIFY * HTTP/1.1\r\nNTS: ssdp:byebye\r\nLOCATION: http://a/\r\n\r\n") == nil)
        #expect(SSDP.parse("HTTP/1.1 200 OK\r\nST: x\r\n\r\n") == nil)
        #expect(SSDP.parse("NOTIFY * HTTP/1.1\r\nNTS: ssdp:alive\r\nNT: x\r\nLOCATION: http://a:1/d.xml\r\n\r\n") != nil)
    }

    static let sonosDescription = """
        <?xml version="1.0" encoding="utf-8" ?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>192.168.2.8 - Sonos One SL - RINCON_38420B7E66AA01400</friendlyName>
            <manufacturer>Sonos, Inc.</manufacturer>
            <modelName>Sonos One SL</modelName>
            <UDN>uuid:RINCON_38420B7E66AA01400</UDN>
            <roomName>Living Room</roomName>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ZoneGroupTopology:1</serviceType>
                <controlURL>/ZoneGroupTopology/Control</controlURL>
              </service>
            </serviceList>
            <deviceList>
              <device>
                <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
                <UDN>uuid:RINCON_38420B7E66AA01400_MS</UDN>
              </device>
              <device>
                <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
                <friendlyName>Living Room - Sonos One SL Media Renderer</friendlyName>
                <UDN>uuid:RINCON_38420B7E66AA01400_MR</UDN>
                <serviceList>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                    <controlURL>/MediaRenderer/RenderingControl/Control</controlURL>
                  </service>
                  <service>
                    <serviceType>urn:schemas-sonos-com:service:Queue:1</serviceType>
                    <controlURL>/MediaRenderer/Queue/Control</controlURL>
                  </service>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:GroupRenderingControl:1</serviceType>
                    <controlURL>/MediaRenderer/GroupRenderingControl/Control</controlURL>
                  </service>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                    <controlURL>/MediaRenderer/AVTransport/Control</controlURL>
                  </service>
                </serviceList>
              </device>
            </deviceList>
          </device>
        </root>
        """

    @Test func readsASonosDescription() throws {
        let location = try #require(URL(string: "http://192.168.2.8:1400/xml/device_description.xml"))
        let description = try #require(UPnPDescription(xml: Self.sonosDescription, location: location))
        #expect(description.udn == "RINCON_38420B7E66AA01400")
        #expect(description.isSonos)
        #expect(description.name == "Living Room")
        #expect(description.avTransport?.absoluteString == "http://192.168.2.8:1400/MediaRenderer/AVTransport/Control")
        // Not GroupRenderingControl, which comes after it here.
        #expect(description.renderingControl?.absoluteString
            == "http://192.168.2.8:1400/MediaRenderer/RenderingControl/Control")
    }

    @Test func readsAPlainRenderer() throws {
        let xml = """
            <root xmlns="urn:schemas-upnp-org:device-1-0"><URLBase>http://10.0.0.5:49152/</URLBase><device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>Kitchen &amp; Bath</friendlyName><manufacturer>Acme</manufacturer>
            <UDN>uuid:1234</UDN><serviceList><service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <controlURL>upnp/control/avt</controlURL></service></serviceList></device></root>
            """
        let description = try #require(UPnPDescription(xml: xml, location: URL(string: "http://10.0.0.5:49152/desc.xml")!))
        #expect(!description.isSonos)
        #expect(description.name == "Kitchen & Bath")
        #expect(description.avTransport?.absoluteString == "http://10.0.0.5:49152/upnp/control/avt")
        #expect(description.renderingControl == nil)
    }

    @Test func oneRowARoomGroupedByCoordinator() {
        // Two rooms playing together, a home theatre with an invisible
        // surround and a satellite, and a room on its own.
        let state = """
            <ZoneGroupState><ZoneGroups>
            <ZoneGroup Coordinator="RINCON_B" ID="RINCON_B:1">
              <ZoneGroupMember UUID="RINCON_A" Location="http://10.0.0.1:1400/xml/device_description.xml" ZoneName="Kitchen"/>
              <ZoneGroupMember UUID="RINCON_B" Location="http://10.0.0.2:1400/xml/device_description.xml" ZoneName="Living Room">
                <Satellite UUID="RINCON_S" Location="http://10.0.0.9:1400/xml/device_description.xml" ZoneName="Living Room" Invisible="1"/>
              </ZoneGroupMember>
              <ZoneGroupMember UUID="RINCON_C" Location="http://10.0.0.3:1400/xml/device_description.xml" ZoneName="Living Room" Invisible="1"/>
            </ZoneGroup>
            <ZoneGroup Coordinator="RINCON_D" ID="RINCON_D:2">
              <ZoneGroupMember UUID="RINCON_D" Location="http://10.0.0.4:1400/xml/device_description.xml" ZoneName="Bed &amp; Room"/>
            </ZoneGroup>
            </ZoneGroups><VanishedDevices></VanishedDevices></ZoneGroupState>
            """
        let groups = SonosGroup.groups(fromZoneGroupState: state)
        #expect(groups.map(\.name) == ["Bed & Room", "Living Room + Kitchen"])
        #expect(groups[1].coordinator == "RINCON_B")
        #expect(groups[1].location.host == "10.0.0.2")
    }

    @Test func readsTheTopologyOutOfItsAnswer() throws {
        // As the speaker sends it: the topology escaped inside the answer.
        let response = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetZoneGroupStateResponse xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1"><ZoneGroupState>&lt;ZoneGroupState&gt;&lt;ZoneGroups&gt;&lt;ZoneGroup Coordinator=&quot;RINCON_38420B7E66AA01400&quot; ID=&quot;RINCON_38420B7E66AA01400:3560209285&quot;&gt;&lt;ZoneGroupMember UUID=&quot;RINCON_38420B7E66AA01400&quot; Location=&quot;http://192.168.2.8:1400/xml/device_description.xml&quot; ZoneName=&quot;Living Room&quot; Icon=&quot;&quot; Configuration=&quot;1&quot;/&gt;&lt;/ZoneGroup&gt;&lt;/ZoneGroups&gt;&lt;VanishedDevices&gt;&lt;/VanishedDevices&gt;&lt;/ZoneGroupState&gt;</ZoneGroupState></u:GetZoneGroupStateResponse></s:Body></s:Envelope>
            """
        let values = try UPnPSOAP.values(in: response, action: "GetZoneGroupState")
        let groups = SonosGroup.groups(fromZoneGroupState: try #require(values["ZoneGroupState"]))
        #expect(groups.map(\.name) == ["Living Room"])
        #expect(groups.first?.location.absoluteString == "http://192.168.2.8:1400/xml/device_description.xml")
    }

    @Test func theSongsAddressSurvivesBothLayers() throws {
        let url = try #require(URL(string: "http://192.168.2.15:8096/Audio/abc/universal?UserId=u&Container=mp3&api_key=t"))
        let didl = DIDLLite.metadata(url: url, contentType: "audio/mpeg", title: "Rock & Roll <live>",
                                     artist: "AC/DC", album: "Album \"One\"", artworkURL: URL(string: "http://h/i?a=1&b=2"),
                                     duration: 201.4)
        #expect(didl.contains("<dc:title>Rock &amp; Roll &lt;live&gt;</dc:title>"))
        #expect(didl.contains("<upnp:albumArtURI>http://h/i?a=1&amp;b=2</upnp:albumArtURI>"))
        #expect(didl.contains("protocolInfo=\"http-get:*:audio/mpeg:*\" duration=\"0:03:21.000\""))
        #expect(didl.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))

        let envelope = UPnPSOAP.envelope("SetAVTransportURI", service: UPnPSOAP.avTransport,
                                         [("InstanceID", "0"), ("CurrentURI", url.absoluteString),
                                          ("CurrentURIMetaData", didl)])
        #expect(envelope.contains("<CurrentURI>http://192.168.2.15:8096/Audio/abc/universal?UserId=u&amp;Container=mp3&amp;api_key=t</CurrentURI>"))
        // The DIDL is text in the envelope: escaped once more.
        #expect(envelope.contains("&lt;DIDL-Lite"))
        #expect(envelope.contains("api_key=t&lt;/res&gt;"))
        #expect(envelope.contains("Container=mp3&amp;amp;api_key"))
        #expect(envelope.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))

        // And read back as the speaker reads it: the same address.
        let body = try #require(UPnPXML.elements("SetAVTransportURI", in: envelope).first)
        let arguments = Dictionary(UPnPXML.children(of: body).map { ($0.name, $0.text) }, uniquingKeysWith: { a, _ in a })
        #expect(arguments["CurrentURI"] == url.absoluteString)
        #expect(arguments["CurrentURIMetaData"] == didl)
        #expect(UPnPXML.text("res", in: didl) == url.absoluteString)
        #expect(UPnPXML.text("title", in: didl) == "Rock & Roll <live>")
    }

    @Test func theHeaderNamesServiceAndAction() {
        #expect(UPnPSOAP.header("Play", service: UPnPSOAP.avTransport)
            == "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    @Test func readsWhereItIs() throws {
        let response = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><Track>1</Track><TrackDuration>0:03:21</TrackDuration><TrackMetaData>&lt;DIDL-Lite&gt;&lt;/DIDL-Lite&gt;</TrackMetaData><TrackURI>http://h/a?x=1&amp;y=2</TrackURI><RelTime>0:01:02</RelTime><AbsTime>NOT_IMPLEMENTED</AbsTime><RelCount>2147483647</RelCount><AbsCount>2147483647</AbsCount></u:GetPositionInfoResponse></s:Body></s:Envelope>
            """
        let values = try UPnPSOAP.values(in: response, action: "GetPositionInfo")
        #expect(values["RelTime"].flatMap(UPnPTime.seconds) == 62)
        #expect(values["TrackDuration"].flatMap(UPnPTime.seconds) == 201)
        #expect(values["TrackURI"] == "http://h/a?x=1&y=2")
        #expect(values["TrackMetaData"] == "<DIDL-Lite></DIDL-Lite>")
        #expect(values["AbsTime"].flatMap(UPnPTime.seconds) == nil)
    }

    @Test func aFaultThrows() {
        let response = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>714</errorCode></UPnPError></detail></s:Fault></s:Body></s:Envelope>
            """
        #expect(throws: UPnPError.fault(code: 714, description: "UPnPError")) {
            try UPnPSOAP.values(in: response, action: "SetAVTransportURI")
        }
    }

    @Test func timeBothWays() {
        #expect(UPnPTime.string(0) == "0:00:00")
        #expect(UPnPTime.string(201.9) == "0:03:21")
        #expect(UPnPTime.string(3725) == "1:02:05")
        #expect(UPnPTime.seconds("0:03:21.500") == 201.5)
        #expect(UPnPTime.seconds("NOT_IMPLEMENTED") == nil)
    }

    @Test func takesOnlyAnswersToItsOwnQuestion() {
        let ok = "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.2.8:1400/d.xml\r\nST: \(SSDP.zonePlayer)\r\n\r\n"
        let searched = [SSDP.zonePlayer, SSDP.mediaRenderer]
        #expect(SSDP.answer(ok, searched: searched, from: "192.168.2.8") != nil)
        // From another address than its description's.
        #expect(SSDP.answer(ok, searched: searched, from: "192.168.2.66") == nil)
        // For something not asked.
        #expect(SSDP.answer(ok, searched: [SSDP.mediaRenderer], from: "192.168.2.8") == nil)
        // A NOTIFY is no answer.
        let notify = "NOTIFY * HTTP/1.1\r\nNTS: ssdp:alive\r\nNT: \(SSDP.zonePlayer)\r\nLOCATION: http://192.168.2.8:1400/d.xml\r\n\r\n"
        #expect(SSDP.answer(notify, searched: searched, from: "192.168.2.8") == nil)
        // A description on the internet.
        let away = "HTTP/1.1 200 OK\r\nLOCATION: http://8.8.8.8/d.xml\r\nST: \(SSDP.zonePlayer)\r\n\r\n"
        #expect(SSDP.answer(away, searched: searched, from: "8.8.8.8") == nil)
    }

    @Test func onlyAddressesInTheHouse() {
        let local = ["http://192.168.1.2:1400/", "http://10.0.0.5/", "http://172.20.1.1/", "http://169.254.3.4/",
                     "http://127.0.0.1:8080/", "http://localhost:9/", "http://[fe80::1]:1400/",
                     "http://[fd12:3456::1]/", "http://[::1]/"]
        let away = ["http://8.8.8.8/", "http://172.32.0.1/", "http://192.169.0.1/", "http://sonos.example.com/",
                    "http://0xc0.168.1.1/", "http://3232235777/", "http://192.168.1/", "http://[2001:db8::1]/",
                    "http://[fc::1]/", "file:///etc/passwd", "ftp://192.168.1.2/"]
        for text in local { #expect(UPnPAddress.isLocal(URL(string: text)!), "\(text)") }
        for text in away { #expect(!UPnPAddress.isLocal(URL(string: text)!), "\(text)") }
    }

    @Test func controlsStayOnTheDescriptionsHost() throws {
        let xml = """
            <root><URLBase>http://10.0.0.99:80/</URLBase><device><UDN>uuid:1</UDN><serviceList>
            <service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <controlURL>avt</controlURL></service>
            <service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <controlURL>http://10.0.0.99/rc</controlURL></service></serviceList></device></root>
            """
        let description = try #require(UPnPDescription(xml: xml, location: URL(string: "http://10.0.0.5:49152/d.xml")!))
        // The URLBase elsewhere is not taken; the control there neither.
        #expect(description.avTransport?.absoluteString == "http://10.0.0.5:49152/avt")
        #expect(description.renderingControl == nil)
    }

    @Test func aSpeakersAnswerIsBoundedAndFromItself() async throws {
        let location = try #require(URL(string: "http://10.0.0.5:1400/d.xml"))
        let xml = "<root><device><UDN>uuid:1</UDN></device></root>"
        let plain = SpeakerFake(HTTPResponse(status: 200, body: Data(xml.utf8), url: location))
        #expect(try await UPnPRenderer.description(at: location, transport: plain).udn == "1")
        // Redirected to another host.
        let moved = SpeakerFake(HTTPResponse(status: 200, body: Data(xml.utf8), url: URL(string: "http://10.0.0.6/d.xml")))
        await #expect(throws: UPnPError.notLocal) { try await UPnPRenderer.description(at: location, transport: moved) }
        // Too big.
        let big = SpeakerFake(HTTPResponse(status: 200, body: Data(count: UPnPRenderer.maximumBytes + 1), url: location))
        await #expect(throws: UPnPError.unreadable) { try await UPnPRenderer.description(at: location, transport: big) }
        // Not in the house: not asked at all.
        let away = try #require(URL(string: "http://8.8.8.8/d.xml"))
        await #expect(throws: UPnPError.notLocal) { try await UPnPRenderer.description(at: away, transport: plain) }
        await #expect(throws: UPnPError.notLocal) {
            try await UPnPRenderer.call(away, UPnPSOAP.avTransport, "Play", [], transport: plain)
        }
        #expect(plain.asked == 1)
    }
}

private final class SpeakerFake: HTTPTransport, @unchecked Sendable {
    let answer: HTTPResponse
    var asked = 0
    init(_ answer: HTTPResponse) { self.answer = answer }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        asked += 1
        return answer
    }
}
