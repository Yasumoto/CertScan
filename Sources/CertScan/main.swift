import Foundation

import Iam

var args = CommandLine.arguments

if (args.contains("--help") || args.contains("-h")) {
    print("CertScan <certificate-prefix>")
    print("Built from https://github.com/Yasumoto/CertScan")
    exit(1)
}

guard args.count == 2, let certPrefix = args.popLast() else {
    print("Please specify the certificate name you'd like to search for!")
    exit(1)
}

let client = Iam()
let request = Iam.ListServerCertificatesRequest(marker: certPrefix, maxItems: nil, pathPrefix: nil)

let response = try client.listServerCertificates(request)
for cert in response.serverCertificateMetadataList {
    print(cert.serverCertificateName)
}
