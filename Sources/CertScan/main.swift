import Foundation

import Iam
import NIOOpenSSL

var args = CommandLine.arguments

if (args.contains("--help") || args.contains("-h")) {
    print("CertScan <certificate-path>")
    print("Built from https://github.com/Yasumoto/CertScan")
    exit(1)
}

guard args.count == 2, let certificatePath = args.popLast() else {
    print("Please specify the path to the certificate you'd like to search for!")
    exit(1)
}

guard let searchCertificate = try? OpenSSLCertificate(file: certificatePath, format: .pem) else {
    print("Could not read \(certificatePath) as a PEM-encoded certificate!")
    exit(1)
}

let client = Iam()
let request = Iam.ListServerCertificatesRequest(marker: nil, maxItems: nil, pathPrefix: nil)

let response = try client.listServerCertificates(request)
for cert in response.serverCertificateMetadataList {
    let getCertificateRequest = Iam.GetServerCertificateRequest(serverCertificateName: cert.serverCertificateName)
    let getCertificateResponse = try client.getServerCertificate(getCertificateRequest)
    var body = getCertificateResponse.serverCertificate.certificateBody
    if body.range(of: "-----BEGIN CERTIFICATE-----\n") == nil {
        body = body.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "-----BEGIN CERTIFICATE-----\n")
    }
    if body.range(of: "-----END CERTIFICATE-----\n") == nil {
        body = body.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "\n-----END CERTIFICATE-----")
    }
    var bodyUnsignedData: [UInt8] = Array(body.utf8)
    bodyUnsignedData.append(0)
    let bodyData: [Int8] = bodyUnsignedData.map { Int8(bitPattern: $0) }
    do {
        let serverCertificate = try OpenSSLCertificate(buffer: bodyData, format: .pem)
        if serverCertificate == searchCertificate {
            print("The certificate is: \(cert.serverCertificateName)")
        }
    } catch {
        print("Could not parse \(cert.serverCertificateName): \(error)")
    }
}

