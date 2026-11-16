/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Security

/// Test PKI generated with OpenSSL 4.1. Certificates are valid from 2026-11-01 to 2027-11-01 (UTC).
/// Pins are `openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64`.
/// No private key is kept.
internal enum TLSPinningFixtures {
    static let host = "flags-pinning.example.com"
    /// A time within the validity period of every certificate.
    static let verificationDate = Date(timeIntervalSince1970: 1_796_083_200) // 2026-12-01T00:00:00Z

    static let pinP256 = "q0QmjYqYGEhBPUOMZdBkKRJMoM729S5QBZUOzK0uFd0="
    static let pinP384 = "AGgHdhXb701nudhobjFnF1YWpQKtUine7uzXhYX2+v8="
    static let pinRSA2048 = "bwueJWXwCqGvhpxflU4gk0Pasvg7/n9cVkTC/pZ+X40="
    static let pinRSA4096 = "M0GcaWpQbE74PxICeOR70EUa1prHftr5xJ7UkpupSC8="
    static let pinRoot = "2eu2AkiN4elC+SGOuK/0U1U0jDQu9BqwcCZoyCox0os="
    /// The pin of a P-256 key that no certificate here uses.
    static let pinUnused = "kq7D9BST1s4dj/8jaowi/59qtN9aoslyEaXp0nXQ8vw="

    /// Self-signed EC P-256 root that issues every leaf below.
    static let root = certificate("""
        MIIBiDCCAS6gAwIBAgIUZdbCCGiD7upQFtmmRTOyiKne+ZowCgYIKoZIzj0EAwIwIjEgMB4GA1UEAwwXRmxhZ3MgUGlubmluZyBU
        ZXN0IFJvb3QwHhcNMjYxMTAxMDAwMDAwWhcNMjcxMTAxMDAwMDAwWjAiMSAwHgYDVQQDDBdGbGFncyBQaW5uaW5nIFRlc3QgUm9v
        dDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNRjd39k6rvyZ93QADHtnV93uQMgrz6IYhA5DkqD/XVPq9TV36+mv/WdS9HlFeaa
        o0yvO5wNlwO9hemr41kKxT6jQjBAMB0GA1UdDgQWBBR4dVbg6GroJPTePHmdBYia+sG7xzAPBgNVHRMBAf8EBTADAQH/MA4GA1Ud
        DwEB/wQEAwIBBjAKBggqhkjOPQQDAgNIADBFAiEA15hTx2lEh1G1w8a368B6uQdPMU8cC2pKpP9mWHDq9lwCIDp0r1RmpWgqoEWA
        1CzgLk3gIchMqdgI9AVGKkFAXHiw
        """)

    /// EC P-256 leaf for `flags-pinning.example.com` (key A).
    static let leafP256 = certificate("""
        MIIBmDCCAT2gAwIBAgIIKSRnHgYYdw4wCgYIKoZIzj0EAwIwIjEgMB4GA1UEAwwXRmxhZ3MgUGlubmluZyBUZXN0IFJvb3QwHhcN
        MjYxMTAxMDAwMDAwWhcNMjcxMTAxMDAwMDAwWjAkMSIwIAYDVQQDDBlmbGFncy1waW5uaW5nLmV4YW1wbGUuY29tMFkwEwYHKoZI
        zj0CAQYIKoZIzj0DAQcDQgAEcTPcsA6iBQlh8DtKUIT7r9KG4YTJtk/xCw9SZUOhxUwnfPdgDjaQwsWYPdHWzkME0VSUByOAvd6z
        vHOjReYgEaNbMFkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBaAwEwYDVR0lBAwwCgYIKwYBBQUHAwEwJAYDVR0RBB0wG4IZ
        ZmxhZ3MtcGlubmluZy5leGFtcGxlLmNvbTAKBggqhkjOPQQDAgNJADBGAiEAuRbrEyxfF+bQ2AIMxDwy/+C2X862tcT7XAXuXJC4
        qMMCIQDGlXBrsi73aOVbN7IHHXKlsxBuUA2b/yU47r+P4CeSwQ==
        """)

    /// EC P-384 leaf for `flags-pinning.example.com` (key B).
    static let leafP384 = certificate("""
        MIIBtTCCAVugAwIBAgIJAKvR3kwZPY5pMAoGCCqGSM49BAMCMCIxIDAeBgNVBAMMF0ZsYWdzIFBpbm5pbmcgVGVzdCBSb290MB4X
        DTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFtcGxlLmNvbTB2MBAGByqG
        SM49AgEGBSuBBAAiA2IABKOiLeItR8STMjyIYK46fASvxMcjREG7efNN/gWoDLYxVtrN7JHFeH6bJyFiT2TYmGtXqDUvSlPuWAdx
        pWGcns9DZcyx+AegtQa2KfbA5OiLBubah2+EQzKs03y4scHEd6NbMFkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBaAwEwYD
        VR0lBAwwCgYIKwYBBQUHAwEwJAYDVR0RBB0wG4IZZmxhZ3MtcGlubmluZy5leGFtcGxlLmNvbTAKBggqhkjOPQQDAgNIADBFAiEA
        2v6jXLEK2VBcsjIlgRqEWKJhenbV+RogMeUhBq9RRKYCIGq3Im5HO9kuIP7N/VB4X1SSA0Ft/N4Kcso+Qle9e9xB
        """)

    /// RSA 2048 leaf for `flags-pinning.example.com`.
    static let leafRSA2048 = certificate("""
        MIICYzCCAgmgAwIBAgIJALuMZzeIXhOcMAoGCCqGSM49BAMCMCIxIDAeBgNVBAMMF0ZsYWdzIFBpbm5pbmcgVGVzdCBSb290MB4X
        DTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFtcGxlLmNvbTCCASIwDQYJ
        KoZIhvcNAQEBBQADggEPADCCAQoCggEBAIoxo4N8a6z2dpYudM21EpQ0bFxzFhYpv8W2NkXGsmX+dfuu1+Dk5Pjb2g/6CsjS/gTM
        9ULn42VmDDj+l/WnTy51s0MG/7bYjCMpnABXMThaXMJKrL9qFJgollCG9CGcfemHGwSomAKrTwMOINvjrXPNE/80u8+on2Otfgao
        f6sGa3WjwXERsODdTx2uQzWMMXCUHwc+sr6gIcLHu1GubGCOKfbnZJ/iZI5nHKbb/srMYgiapKRml6IDaRKaTE/ZwWew87KXvprw
        l+4oWmEuHmp7PLg2hOYVMRmH1UKWf+a8vrJHqSNxxdMmVFnDb2nOImCUi0sepuPnWZKB05fQNSMCAwEAAaNbMFkwDAYDVR0TAQH/
        BAIwADAOBgNVHQ8BAf8EBAMCBaAwEwYDVR0lBAwwCgYIKwYBBQUHAwEwJAYDVR0RBB0wG4IZZmxhZ3MtcGlubmluZy5leGFtcGxl
        LmNvbTAKBggqhkjOPQQDAgNIADBFAiBcpD3k40jShzehdUWAI3QGzQtGDK5Nwt0DftS8Mncq/gIhAMdSiZKXPLB6Y5Jm9nejrKrm
        4coDMNU2YGsGD/Uby9Hq
        """)

    /// RSA 4096 leaf for `flags-pinning.example.com`.
    static let leafRSA4096 = certificate("""
        MIIDYzCCAwmgAwIBAgIJAJwWKtpwb6iEMAoGCCqGSM49BAMCMCIxIDAeBgNVBAMMF0ZsYWdzIFBpbm5pbmcgVGVzdCBSb290MB4X
        DTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFtcGxlLmNvbTCCAiIwDQYJ
        KoZIhvcNAQEBBQADggIPADCCAgoCggIBAKlF9AJS0AlpyVS+/9EycNf3DzhknnEX5J+BCkz63V2Q/56XtVJX6XAyKe+lii20HnFS
        7CjNqhyuKxOkk+K8Jci6gE2mpKYrSL8VZO4KdTPBlogcHuaBSXtBFPxoDIE5OFs4lvL7CfD8AS6N8zTfTZhCVuJT/2lykHf0whqu
        RomXpPC4S2qM7Tt8c4f0+NU1Wn5Is+y0Y7eb+gKCdCrg9fOg2gaWrKF3qj6TxwU4jo1CH6gIfxA+aWLbwrK5u+8FBIPq9u0aXkOM
        3b7ORM0uGrE/LKKg3ojfvQDvVwRAbmMhEVj79q/DBvXJpp93eCpla1pcreO72Z0h7LTp/+svD1KxS09iToHygzUMVccnxYOloihx
        lodUErtaPBR6ysMng814Qr+dw8T1bHZGUNpRajBXPwZUowQwbl24rbNsxG5JfBDsPOp5QTzLdGNEnhRCY+7Q8osoKC1P5PLAK1A4
        h+G1tYz9hvLrakXmu7n1J2CcFF55Qog1Q09vuXPQqgJ5Ou37TnwJGhEeV9dDrWx6TKqhRh695bap42sSY5DN4wnAaU8uyCIHwFN8
        RqVeLPWO1n9OeLrQpWfnwUqwT5DyYZy70FwdaBpbWWHZB5lGtBPjgM8IMVTSFEvHF20viSieyQfoatPtMLANNst/nNcsHrzbR0u+
        hHsZforp2zz8u/ltAgMBAAGjWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQG
        A1UdEQQdMBuCGWZsYWdzLXBpbm5pbmcuZXhhbXBsZS5jb20wCgYIKoZIzj0EAwIDSAAwRQIgZJrlV03X75hEJzpy0s4kF0HXCgUd
        gHgSfaqoqTBqNj0CIQCa+IzZmAk5JVhVddBq5SEla1xSBb0sIitxT06Qgsz4Qg==
        """)

    /// EC P-256 leaf for `other.example.com` with key A.
    static let leafP256OtherHost = certificate("""
        MIIBiDCCAS6gAwIBAgIJAMDHRkpqc63IMAoGCCqGSM49BAMCMCIxIDAeBgNVBAMMF0ZsYWdzIFBpbm5pbmcgVGVzdCBSb290MB4X
        DTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowHDEaMBgGA1UEAwwRb3RoZXIuZXhhbXBsZS5jb20wWTATBgcqhkjOPQIBBggq
        hkjOPQMBBwNCAARxM9ywDqIFCWHwO0pQhPuv0obhhMm2T/ELD1JlQ6HFTCd892AONpDCxZg90dbOQwTRVJQHI4C93rO8c6NF5iAR
        o1MwUTAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcDATAcBgNVHREEFTATghFvdGhlci5l
        eGFtcGxlLmNvbTAKBggqhkjOPQQDAgNIADBFAiAJlGTpHWketFcqYdY8JkFV/2tjEPGDxqmgOWqGjf9MLwIhAJipSzb/69hl5S1C
        vukSGNI2bICQgTd2YJJCjSzU5khF
        """)

    private static func certificate(_ base64: String) -> SecCertificate {
        // swiftlint:disable:next force_unwrapping
        let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
        // swiftlint:disable:next force_unwrapping
        return SecCertificateCreateWithData(nil, der as CFData)!
    }
}
