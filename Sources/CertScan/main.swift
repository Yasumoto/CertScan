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
    let body = getCertificateResponse.serverCertificate.certificateBody
    if let byteBody = body.cString(using: .utf8), let serverCertificate = try? OpenSSLCertificate(buffer:
        byteBody, format: .pem) {
        print("The certificate is: \(cert.serverCertificateName)")
        print(serverCertificate)
        print("The same as what we look for: \(serverCertificate == searchCertificate)")
    }
}

