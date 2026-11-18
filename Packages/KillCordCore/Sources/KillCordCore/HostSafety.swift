import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Keeps custom connections off the person's own network: no loopback, private, link-local, carrier-grade
/// NAT, multicast or reserved addresses, whether typed in or resolved from a name. Kill Cord checks the
/// addresses right before each request; a name that changes what it resolves to between that check and the
/// connection is a known gap, narrowed by also refusing local names.
public enum HostSafety {
    /// Why a host can't be used, or nil when it's fine.
    public static func problem(host: String, addresses: [String]?) -> String? {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local")
            || name.hasSuffix(".internal") || name.hasSuffix(".lan") || !name.contains(".") && !name.contains(":") {
            return "that's a name on your own network, so Kill Cord won't call it."
        }
        if isIPLiteral(name), !isPublic(name) {
            return "that address is on a private or local network, so Kill Cord won't call it."
        }
        guard let addresses, !addresses.isEmpty else { return nil }
        if addresses.contains(where: { !isPublic($0) }) {
            return "that name points to a private or local network address, so Kill Cord won't call it."
        }
        return nil
    }

    static func isIPLiteral(_ text: String) -> Bool { ipv4(text) != nil || ipv6(text) != nil }

    /// True for a routable public address. Anything that doesn't parse counts as not public.
    public static func isPublic(_ address: String) -> Bool {
        if let octets = ipv4(address) { return isPublicV4(octets) }
        if let bytes = ipv6(address) { return isPublicV6(bytes) }
        return false
    }

    static func isPublicV4(_ octets: [UInt8]) -> Bool {
        let (first, second) = (octets[0], octets[1])
        switch first {
        case 0, 10, 127: return false                       // this network, private, loopback
        case 100 where (64...127).contains(second): return false // carrier-grade NAT
        case 169 where second == 254: return false               // link-local
        case 172 where (16...31).contains(second): return false  // private
        case 192 where second == 168: return false               // private
        case 192 where second == 0 && octets[2] == 0: return false // IETF protocol assignments
        case 198 where second == 18 || second == 19: return false     // benchmarking
        case 224...255: return false                        // multicast, reserved, broadcast
        default: return true
        }
    }

    static func isPublicV6(_ bytes: [UInt8]) -> Bool {
        // IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible forms follow the IPv4 rules.
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return isPublicV4(Array(bytes[12..<16]))
        }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) { return false } // :: and ::1
        if bytes[0] & 0xfe == 0xfc { return false }               // unique local fc00::/7
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return false } // link-local fe80::/10
        if bytes[0] == 0xff { return false }                      // multicast
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 { return false } // documentation
        return true
    }

    static func ipv4(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> UInt8? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber) else { return nil }
            return UInt8(part)
        }
        return octets.count == 4 ? octets : nil
    }

    static func ipv6(_ text: String) -> [UInt8]? {
        guard text.contains(":") else { return nil }
        var storage = in6_addr()
        let parsed = text.withCString { inet_pton(AF_INET6, $0, &storage) } == 1
        guard parsed else { return nil }
        return withUnsafeBytes(of: &storage) { Array($0) }
    }

    /// Every address a name resolves to, IPv4 and IPv6. Nil when it doesn't resolve.
    public static func resolve(_ host: String) -> [String]? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
                           NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
            cursor = info.pointee.ai_next
        }
        return addresses.isEmpty ? nil : addresses
    }
}
