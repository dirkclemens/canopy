import Foundation
import Security
import CocoaMQTT

enum CertificateError: LocalizedError {
    case invalidCACertificate(String)
    case invalidClientIdentity(String)

    var errorDescription: String? {
        switch self {
        case .invalidCACertificate(let name): "CA-Zertifikat „\(name)“ ist ungültig"
        case .invalidClientIdentity(let reason): "Client-Zertifikat/Schlüssel ungültig: \(reason)"
        }
    }
}

enum CertificateLoader {

    /// Parses a PEM bundle (one or more certificates) or a single DER certificate.
    static func certificates(from data: Data) -> [SecCertificate] {
        if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") {
            return pemBlocks(in: text, label: "CERTIFICATE").compactMap {
                SecCertificateCreateWithData(nil, $0 as CFData)
            }
        }
        return SecCertificateCreateWithData(nil, data as CFData).map { [$0] } ?? []
    }

    /// Human readable subject summary of the first certificate in `data`.
    static func summary(of data: Data) -> String? {
        guard let certificate = certificates(from: data).first else { return nil }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }

    static func caCertificates(for file: ImportedFile) throws -> [SecCertificate] {
        let certificates = certificates(from: file.data)
        if certificates.isEmpty { throw CertificateError.invalidCACertificate(file.fileName) }
        return certificates
    }

    static func clientIdentity(certificate: Data, key: Data) throws -> CocoaMQTTClientIdentity {
        do {
            return try CocoaMQTTClientIdentity(certificateData: certificate, privateKeyData: key)
        } catch {
            throw CertificateError.invalidClientIdentity(String(describing: error))
        }
    }

    private static func pemBlocks(in text: String, label: String) -> [Data] {
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        var blocks: [Data] = []
        var remainder = Substring(text)
        while let start = remainder.range(of: begin),
              let stop = remainder.range(of: end, range: start.upperBound..<remainder.endIndex) {
            let base64 = remainder[start.upperBound..<stop.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: base64) { blocks.append(data) }
            remainder = remainder[stop.upperBound...]
        }
        return blocks
    }
}
