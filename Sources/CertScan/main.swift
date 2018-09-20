import Foundation

import Cloudfront
import Elasticloadbalancing
import Elasticloadbalancingv2
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

func findIamCertificate(_ desiredCertificate: OpenSSLCertificate) throws -> Iam.ServerCertificateMetadata? {
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
                print("The matching certificate is: \(cert.serverCertificateName)")
                return cert
            }
        } catch {
            print("Could not parse \(cert.serverCertificateName): \(error)")
        }
    }
    return nil
}

func searchClassicLoadBalancers(matchingArn: String) throws -> [String] {
    let client = Elasticloadbalancing()

    func sendRequest(marker: String? = nil) throws -> [String] {
        var matches = [String]()
        let request = Elasticloadbalancing.DescribeAccessPointsInput(marker: nil, loadBalancerNames: nil, pageSize: nil)
        let response = try client.describeLoadBalancers(request)
        if let marker = response.nextMarker {
            print("Guess what, you better handle retries: \(marker)")
        }
        for loadBalancer in response.loadBalancerDescriptions ?? [] {
            for listener in loadBalancer.listenerDescriptions ?? [] {
                if let certificateArn = listener.listener?.sSLCertificateId {
                    if certificateArn == matchingArn {
                        print("Found a match!")
                        if let name = loadBalancer.loadBalancerName, let dns = loadBalancer.dNSName {
                            print("Loadbalancer: \(name)")
                            print("Serving: \(dns)")
                            matches.append(name)
                        }
                    }
                }
            }
        }
        if let nextMarker = response.nextMarker {
            let newMatches = try sendRequest(marker: nextMarker)
            matches = matches + newMatches
        }
        return matches
    }
    return try sendRequest()
}

func searchApplicationLoadBalancers(matchingArn: String) throws -> [String] {
    let client = Elasticloadbalancingv2()

    func sendRequest(marker: String? = nil) throws -> [String] {
        var matches = [String]()
        let request = Elasticloadbalancingv2.DescribeLoadBalancersInput()
        let response = try client.describeLoadBalancers(request)
        if let marker = response.nextMarker {
            print("Guess what, you better handle retries: \(marker)")
        }
        for loadBalancer in response.loadBalancers ?? [] {
            guard let loadBalancerArn = loadBalancer.loadBalancerArn else {
                print("No ARN found for \(loadBalancer)")
                break
            }
            if loadBalancer.type == .network {
                if let name = loadBalancer.loadBalancerName {
                    //print("Found an NLB: \(name)")
                }
                break
            }

            let listenerInput = Elasticloadbalancingv2.DescribeListenersInput(loadBalancerArn: loadBalancerArn)
            print("Querying loadBalancer: \(loadBalancer)")
            let listenerResponse = try client.describeListeners(listenerInput)
            for listener in listenerResponse.listeners ?? [] {
                guard let listenerArn = listener.listenerArn else {
                    break
                }
                let certificatesInput = Elasticloadbalancingv2.DescribeListenerCertificatesInput(listenerArn: listenerArn)
                print("Querying Certificates: \(listener)")
                let certificatesResponse = try client.describeListenerCertificates(certificatesInput)
                for certificate in certificatesResponse.certificates ?? [] {
                    if let certificateArn = certificate.certificateArn {
                        if certificateArn == matchingArn {
                            print("Found a match!")
                            if let name = loadBalancer.loadBalancerName, let dns = loadBalancer.dNSName {
                                print("Loadbalancer: \(name)")
                                print("Serving: \(dns)")
                                matches.append(name)
                            }
                        }
                    }
                }
            }
        }
        if let nextMarker = response.nextMarker {
            let newMatches = try sendRequest(marker: nextMarker)
            matches = matches + newMatches
        }
        return matches
    }
    return try sendRequest()
}

func searchAllDistributions(matchingId: String) throws -> [String] {
    let client = Cloudfront()
    let response = try client.listDistributions(Cloudfront.ListDistributionsRequest())
    if let marker = response.distributionList?.nextMarker {
        print("Guess what, you better handle CloudFront retries: \(marker)")
    }
    var matches = [String]()
    if let distributionList = response.distributionList?.items?.distributionSummary {
        for distribution in distributionList {
            if let certId = distribution.viewerCertificate.iAMCertificateId {
                if matchingId == certId {
                    print("Found a matching CloudFront distribution!")
                    print("ARN: \(distribution.arn)")
                    print("Domain Name: \(distribution.domainName)")
                    print("ID: \(distribution.id)")
                    matches.append(distribution.id)
                }
            }
        }
    }
    return matches
}


guard let match = try findIamCertificate(searchCertificate) else {
    print("Could not find matching IAM certificate!")
    exit(1)
}
let elbs = try searchClassicLoadBalancers(matchingArn: match.arn)
if elbs.isEmpty {
    print("Good news! No ELBs to update.")
}
let albs = try searchApplicationLoadBalancers(matchingArn: match.arn)
if albs.isEmpty {
    print("Good news! No ALBs to update.")
}
let distributions = try searchAllDistributions(matchingId: match.serverCertificateId)
if distributions.isEmpty {
    print("Good news! No CloudFront distributions to update.")
}
