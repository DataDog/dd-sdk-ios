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

    // MARK: - Issuer chain: issuerRoot -> issuerIntermediate -> issuedLeafA / issuedLeafB

    static let pinIssuerRoot = "KJDpDC7/qypv72NJP5ONN77ZXQTj+XApOa/YPMaUmBQ="
    static let pinIssuerIntermediate = "jjk+oJr9W7zobtzAQz6CZOKJ8WYWghAke64hCl0arIY="
    static let pinIssuedLeafA = "4ji0Cqtk3Jfogj4jhfO/7z0AC2w33Athi3sq6qzmMJ0="
    static let pinIssuedLeafB = "VYBqetzd6IoaGeiPkbGQU6iYwJJWG/WA7/T6T+RGTm0="
    static let pinInterceptionRoot = "agYF8YFKLpqTXI4bikQ49ftNlIYNue7mPGBHq1CHuHc="

    /// Self-signed EC P-256 root of the issuer chain.
    static let issuerRoot = certificate("""
        MIIBljCCATygAwIBAgIUIO7RO0CJjMiWBYQm6y3KIwSBMZ4wCgYIKoZIzj0EAwIwKTEnMCUGA1UEAwweRmxhZ3MgUGlubmluZyBJ
        c3N1ZXIgVGVzdCBSb290MB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowKTEnMCUGA1UEAwweRmxhZ3MgUGlubmluZyBJ
        c3N1ZXIgVGVzdCBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEI955JEsprul4aeIqjfyqKUs3wEYO0gX3JGPLKsNc7Wye
        Ws6wA+ek5tVIm76k/UYFElAboebeBqMd4qdaSl8dNaNCMEAwHQYDVR0OBBYEFDtqCOquEsYTZRyfHHgoS8K/a62tMA8GA1UdEwEB
        /wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0gAMEUCIBF9wB+49ccfA0Nxlrn4r8BczDtoTE+jUq95oa3O+tsW
        AiEAyruHqLV2QCoyrNuSknwb13tmGr3YBiKIQyyVYhRFBLM=
        """)

    /// EC P-256 intermediate (`pathlen:0`) signed by `issuerRoot`.
    static let issuerIntermediate = certificate("""
        MIIBdjCCARygAwIBAgIIcS9bwiwgiRgwCgYIKoZIzj0EAwIwKTEnMCUGA1UEAwweRmxhZ3MgUGlubmluZyBJc3N1ZXIgVGVzdCBS
        b290MB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowMTEvMC0GA1UEAwwmRmxhZ3MgUGlubmluZyBJc3N1ZXIgVGVzdCBJ
        bnRlcm1lZGlhdGUwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARuodQlwt3bwAFV9YGObDtNW/3MkCYJoLta8AfqxRyEOSpLSiMB
        P0R+28b/4xB8Zox3Wx91o2X1k2/+l8/prVhvoyYwJDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBBjAKBggqhkjO
        PQQDAgNIADBFAiB0jhy+4iKlDuxfTG5WFTZmW6DnTnXKC3C9E3xKBXFuKgIhAJpl5vX8HqG7dGfcJuTsZwVeRsLaxX4ZrFY+RIYP
        f1cP
        """)

    /// EC P-256 leaf for `flags-pinning.example.com` signed by `issuerIntermediate`.
    static let issuedLeafA = certificate("""
        MIIBpjCCAU2gAwIBAgIJAJJDansMMbnpMAoGCCqGSM49BAMCMDExLzAtBgNVBAMMJkZsYWdzIFBpbm5pbmcgSXNzdWVyIFRlc3Qg
        SW50ZXJtZWRpYXRlMB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFt
        cGxlLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBUsOweH54hJr/HlAUDYbHBtG6sfPCQ0oCymGLnjWWFbdq5mQv3xLuMA
        lRoiD4i1IhnqOoTzGoKbf94vUtNMDX6jWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUF
        BwMBMCQGA1UdEQQdMBuCGWZsYWdzLXBpbm5pbmcuZXhhbXBsZS5jb20wCgYIKoZIzj0EAwIDRwAwRAIgTj2M7rKo426pOqkH8eBw
        t+n5zurc9fAFZeVT32fdUOACIDDFqMvXbkdcN1eHW3iSnOKyZRAWgjKvNUZ1pbwCsW16
        """)

    /// RSA 2048 leaf for `flags-pinning.example.com` signed by `issuerIntermediate`: a renewal with a new key.
    static let issuedLeafB = certificate("""
        MIICcjCCAhigAwIBAgIJAI2anHJ70bDLMAoGCCqGSM49BAMCMDExLzAtBgNVBAMMJkZsYWdzIFBpbm5pbmcgSXNzdWVyIFRlc3Qg
        SW50ZXJtZWRpYXRlMB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFt
        cGxlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALiaOvIqEys3izh77mmLejAzA45bAeQdEQNNKSqWb7Bxz+vR
        3DNpy73I5n8l9D4Yo6S4w1Y5AN873A3sPlX08eNFSsMmem2EEZkh92r3oAlnyJVTSfASgEImOHchIIeilnLFb1PlPIqawg2Va2Mw
        pk+yslZYnuYUCmFD71h/+jWNt9Gi2CtLNGX7OPsOVtvq+O1FDfD5wMhneHqbFquRS44gTKzjI0F/p96gS5tlcHRkqkNiREm9Xd0y
        gQBXib7y9rk3bb9Pd/FG6SOdSBhbifaNqaH1Hi71cOcim7Y6pSraDZtoHc5w4oxOIMTTsL11RGkoMN+CS2VCPx6DPv9Mo+sCAwEA
        AaNbMFkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBaAwEwYDVR0lBAwwCgYIKwYBBQUHAwEwJAYDVR0RBB0wG4IZZmxhZ3Mt
        cGlubmluZy5leGFtcGxlLmNvbTAKBggqhkjOPQQDAgNIADBFAiANFr9EYVeR7SgE8MAJ6JqE8zCSmzHkNejBb364pBpxvAIhANmt
        kI4AK9QyjRfogjCk/6D3EvE+Apf1voguiOI3EFbj
        """)

    /// Another self-signed EC P-256 root, like an interception CA that the device trusts.
    static let interceptionRoot = certificate("""
        MIIBozCCAUigAwIBAgIUPlGRJh21N92ty5SN3DhmoB3G8VswCgYIKoZIzj0EAwIwLzEtMCsGA1UEAwwkRmxhZ3MgUGlubmluZyBJ
        bnRlcmNlcHRpb24gVGVzdCBSb290MB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowLzEtMCsGA1UEAwwkRmxhZ3MgUGlu
        bmluZyBJbnRlcmNlcHRpb24gVGVzdCBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAETQ78uG++rDjeZUZ/PoPqLJdgv+eR
        6u46pvdTT+EbeszaAQibL2MgUJHoJeLoF+WDZzN6nHvzUkLniZCgUQJQoqNCMEAwHQYDVR0OBBYEFEKg6CEqupiXfCljQQyHeMYM
        uTAnMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0kAMEYCIQDf1nH7j/bDeQ4rJD+8z8DrzFRL
        PG+ZKKFtaoZhHWCUsAIhAJTqlncF8oTFqxamqgybyvKpbgB5ZPZ/dRO8KwcV5RIy
        """)

    /// EC P-256 leaf for `flags-pinning.example.com` signed by `interceptionRoot`.
    static let interceptionLeaf = certificate("""
        MIIBpDCCAUqgAwIBAgIITBFzI8LXVpEwCgYIKoZIzj0EAwIwLzEtMCsGA1UEAwwkRmxhZ3MgUGlubmluZyBJbnRlcmNlcHRpb24g
        VGVzdCBSb290MB4XDTI2MTEwMTAwMDAwMFoXDTI3MTEwMTAwMDAwMFowJDEiMCAGA1UEAwwZZmxhZ3MtcGlubmluZy5leGFtcGxl
        LmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKR8zS6jrZxt7Np0lq/ef4tJuKHB/kEJCt3Nl2bcg/osvTsKKyVN/QuJDXV8
        6ZgpD6GW9q9AepMQxY8FrJqSUKGjWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMB
        MCQGA1UdEQQdMBuCGWZsYWdzLXBpbm5pbmcuZXhhbXBsZS5jb20wCgYIKoZIzj0EAwIDSAAwRQIhAPVPN/USYkGXhqghWa+m7sh8
        y20mbeLjfspF1JO3qCSdAiBtF/ZymtEwlV+ksclhzA3UsgBw87XA2lhjSAAWmHI17A==
        """)

    // MARK: - Public Certainly CA certificates (pins of `TLSPinPolicy.datadogStagingV1`)

    /// Certainly Intermediate R1 (RSA 2048), cross-signed by Starfield Root G2, valid to 2032-06-21.
    static let certainlyIntermediateR1 = certificate("""
        MIIEoDCCA4igAwIBAgIIEYMc3ky1c+UwDQYJKoZIhvcNAQELBQAwgY8xCzAJBgNVBAYTAlVTMRAwDgYDVQQIEwdBcml6b25hMRMw
        EQYDVQQHEwpTY290dHNkYWxlMSUwIwYDVQQKExxTdGFyZmllbGQgVGVjaG5vbG9naWVzLCBJbmMuMTIwMAYDVQQDEylTdGFyZmll
        bGQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgLSBHMjAeFw0yMjA2MjIwMDAwMDBaFw0zMjA2MjEyMzU5NTlaMEUxCzAJBgNV
        BAYTAlVTMRIwEAYDVQQKEwlDZXJ0YWlubHkxIjAgBgNVBAMTGUNlcnRhaW5seSBJbnRlcm1lZGlhdGUgUjEwggEiMA0GCSqGSIb3
        DQEBAQUAA4IBDwAwggEKAoIBAQCW0khmsa1kAMrw6Q6kPsiZ6LfWXQcpcDnu1+Ql7+FYYyBKT3zFSsjx+ZTI2yRG2sFOwbBMchtQ
        f5MGUoQfNznRANlqUNXdWlMrkso93JburzqBEoNGy8utK0TNnepMbb1yc4YuXk/nMRZaBPA2Lh8utwUG3vMvNQHsliV48CQ+4CJu
        tM34rvI9AfJeI2CkcxBUlCyYatGcA12nvCr7dGdyEKeG5G4XyBak48571FtQqNqkSkCQlqmv93LVoOHqzEQKcJWw8zPxZc0dnORZ
        VmgLl3Ws/QltCsIf6OTyQOfGHi81ehr6P4j1KQ56MfgWcqBqdeIANxVcb0ZVVb3SiEhTAgMBAAGjggFHMIIBQzASBgNVHRMBAf8E
        CDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwHQYDVR0OBBYEFL2Xnd+h2Bsl
        meMMBAaJZBLXZSTHMB8GA1UdIwQYMBaAFHwMMh+n2TB/xH1oo2Kooc6rB1snMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZC
        aHR0cDovL2NlcnRpZmljYXRlcy5zdGFyZmllbGR0ZWNoLmNvbS9yZXBvc2l0b3J5L3Nmcm9vdC1nMi5jcnQuY2VyMDsGA1UdHwQ0
        MDIwMKAuoCyGKmh0dHA6Ly9jcmwuc3RhcmZpZWxkdGVjaC5jb20vc2Zyb290LWcyLmNybDAhBgNVHSAEGjAYMAgGBmeBDAECATAM
        BgorBgEEAYOGGQEBMA0GCSqGSIb3DQEBCwUAA4IBAQBosoh/lcTPBVC36SxIqjmdnuKwHs4SUDa/o5+yAJ22DaZDIFMJS+LLhslC
        VPAO9lQ5LR0AviC8atueKWOxPUw5aNDodEpIe988xSNaLSuPXsAB93FJ5v2BxdCiDHlIZbJPAOVQAo+rP2WgaTcDFX6g6LvK1b/R
        S9kL+rCBOebvFIbOmhfErkXjR7F6p759ftTQ23tT1qoTgegkySRgugEp0mtveWq87UIsGgdIe3UVWONiA9l3hTmxRyHkaYLlBzDd
        VPt4MIUkFrxZAz/8ebh+x2KNfAO6Mxi/vdS09NEqn0ekjRmQK5UvHXoBNHVvZ1VrbMv6hlIMCt++bfb6UBoK
        """)

    /// Certainly Intermediate E1 (EC P-384), signed by Certainly Root E1, valid to 2031-04-01.
    static let certainlyIntermediateE1 = certificate("""
        MIIC2TCCAl+gAwIBAgIRAJYHppJ2acna+Y48FdIY4P0wCgYIKoZIzj0EAwMwPTELMAkGA1UEBhMCVVMxEjAQBgNVBAoTCUNlcnRh
        aW5seTEaMBgGA1UEAxMRQ2VydGFpbmx5IFJvb3QgRTEwHhcNMjEwNDAxMDAwMDAwWhcNMzEwNDAxMDAwMDAwWjBFMQswCQYDVQQG
        EwJVUzESMBAGA1UEChMJQ2VydGFpbmx5MSIwIAYDVQQDExlDZXJ0YWlubHkgSW50ZXJtZWRpYXRlIEUxMHYwEAYHKoZIzj0CAQYF
        K4EEACIDYgAEIytwCy+dJMrSsrBQV/BHqHcm8DElWAncRwx93X/EzltIWYS0yPWohGvkgabOxoYQEL25khqULTyUtdEo3fhpgxil
        on8K6PYRPAn+T+pHt6O14WDig1eg2jRw4ojvYVKLo4IBGTCCARUwDgYDVR0PAQH/BAQDAgGGMB0GA1UdJQQWMBQGCCsGAQUFBwMC
        BggrBgEFBQcDATASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBQKmJiuTzrX3WeG55clWpsjT1tYHTAfBgNVHSMEGDAWgBTz
        KBjLZHXuKSrr7a4jWDiF68giBzA5BggrBgEFBQcBAQQtMCswKQYIKwYBBQUHMAKGHWh0dHA6Ly9yb290LWUxLmNlcnRhaW5seS5j
        b20vMDIGA1UdHwQrMCkwJ6AloCOGIWh0dHA6Ly9jcmwucm9vdC1lMS5jZXJ0YWlubHkuY29tLzAhBgNVHSAEGjAYMAgGBmeBDAEC
        ATAMBgorBgEEAYOGGQEBMAoGCCqGSM49BAMDA2gAMGUCMQCMTsYZ58bD1gHwU+ENg8QOsQcX6eqZtkX0B3XW2sBgw95cqTHXPKU5
        PxDc1mG2sXMCMDytOehXbAYtAokk5ll5M96ze3Q2gcaGn90Fl1+yx9ftHEZwGk6pRauHtuPAPfxPEA==
        """)

    /// Certainly Root R1 (RSA 4096), valid to 2046-04-01.
    static let certainlyRootR1 = certificate("""
        MIIFRzCCAy+gAwIBAgIRAI4P+UuQcWhlM1T01EQ5t+AwDQYJKoZIhvcNAQELBQAwPTELMAkGA1UEBhMCVVMxEjAQBgNVBAoTCUNl
        cnRhaW5seTEaMBgGA1UEAxMRQ2VydGFpbmx5IFJvb3QgUjEwHhcNMjEwNDAxMDAwMDAwWhcNNDYwNDAxMDAwMDAwWjA9MQswCQYD
        VQQGEwJVUzESMBAGA1UEChMJQ2VydGFpbmx5MRowGAYDVQQDExFDZXJ0YWlubHkgUm9vdCBSMTCCAiIwDQYJKoZIhvcNAQEBBQAD
        ggIPADCCAgoCggIBANA21B/q3avk0bbm+yLA3RMNansiExyXPGhjZjKcA7WNpIGD2ngwEc/csiu+kr+O5MQTvqRoTNoCaBZ0vrLd
        BORrKt03H2As2/X3oXyVtwxwhi7xOu9S98zTm/mLvg7fMbedaFySpvXl8wo0tf97ouSHocavFwDvA5HtqRxOcT3Si2yJ9HiG5mpJ
        oM610rCrm/b01C7jcvk2xusVtyWMOvwlDbMicyF0yEqWYZL1LwsYpfSt4u5BvQF5+paMjRcCMLT5r3gajLQ2EBAHBXDQ9DGQilHF
        hiZ5shGIXsXwClTNSaa/ApzSRKft43jvRl5tcdF5cBxGX1HpyTfcX35pe0HfNEXgO4T0oYoKNp43zGJS4YkNKPl6I7ENPT2a/Z2B
        7yyQwHtETrtJ4A5KVpK8y7XdeReJkd5hiXSSqOMyhb5OhaRLWcsrxXiOcVTQAjeZjOVJ6uBUcqQRBi8LjMFbvrWhsFNunLhgkR9Z
        a/kt9JQKl7XsxXYDVBtlUrpMklZRNaBA2CnbrlJ2Oy0wQJuK0EJWtLeIAaSHO1OWzaMWj/Nmqhexx2DgwUMFDO6bW2BvBlyHWyf5
        QBGenDPBt+U1VwV/J84XIIwc/PH72jEpSe31C4SnT8H2TsIonPru4K8H+zMReiFPCyEQtkA6qyI6BJyLm4SGcprSp6XEtHWRqSsj
        AgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTgqj8ljZ9EXME66C6ud0yEPmcM9DAN
        BgkqhkiG9w0BAQsFAAOCAgEAuVevuBLaV4OPaAszHQNTVfSVcOQrPbA56/qJYv331hgELyE03fFo8NWWWt7CgKPBjcZq91l3rhVk
        z1t5BXdm6ozTaw3d8VkswTOlMIAVRQdFGjEitpIAq5lNOo93r6kiyi9jyhXWx8bwPWz8HA2YEGGeEaIi1wrykXprOQ4vMMM2SZ/g
        6Q8CRFA3lFV96p/2O7qUpUzpvD5RtOjKkjZUbVwlKNrdrRT90+7iIgXr0PK3aBLXWopBGsaSpVo7Y0VPv+E6dyIvXL9G+VoDhRNC
        X8reU9ditaY1BMJH/5n9hN9czulegChB8n3nHpDYT3Y+gjwN/KUD+nsa2UUeYNrEjvn8K8l7lcUq/6qJ34IxD3L/DCfXCh5WAFAe
        DJDBlrXYFIW7pw0WwfgHJBu6haEaBQmAupVjyTrsJZ9/nbqkRxWbRHDxakvWOF5D8xh+UG7pWijmZeZ3Gzr9Hb4DJqPb1OG7fpYn
        Kx3upPvaJVQTA945xsMfTZDsjxtK0hzthZU4UHlG1sGQUDGpXJpuHfUzVounmdLyyCwzk5Iwx06MZTMQZBf9JBeW0Y3COmor6xOL
        RPIh80oat3df1+2IpHLlOR+Vnb5nwXARPbv0+Em34yaXOp/SX3z7wJl8OSngex2/DaeP0ik0biQVy96QXr8axGbqwua6OV+KmalB
        WQewLK8=
        """)

    /// Certainly Root E1 (EC P-384), valid to 2046-04-01.
    static let certainlyRootE1 = certificate("""
        MIIB9zCCAX2gAwIBAgIQBiUzsUcDMydc+Y2aub/M+DAKBggqhkjOPQQDAzA9MQswCQYDVQQGEwJVUzESMBAGA1UEChMJQ2VydGFp
        bmx5MRowGAYDVQQDExFDZXJ0YWlubHkgUm9vdCBFMTAeFw0yMTA0MDEwMDAwMDBaFw00NjA0MDEwMDAwMDBaMD0xCzAJBgNVBAYT
        AlVTMRIwEAYDVQQKEwlDZXJ0YWlubHkxGjAYBgNVBAMTEUNlcnRhaW5seSBSb290IEUxMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE
        3m/4fxzf7flHh4axpMCK+IKXgOqPyEpeKn2IaKcBYhSRJHpcnqMXfYqGITQYUBsQ3tA3SybHGWCA6TS9YBk2QNYphwk8kXr2vBMj
        3VlOBF7PyAIcGFPBMdjaIOlEjeR2o0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU8ygYy2R1
        7ikq6+2uI1g4hevIIgcwCgYIKoZIzj0EAwMDaAAwZQIxALGOWiDDshliTd6wT99u0nCK8Z9+aozmut6Dacpps6kFtZaSF4fC0urQ
        e87YQVt8rgIwRt7qy12a7DLCZRawTDBcMPPaTnOGBtjOiQRINzf43TNRnXCve1XYAS59BWQOhriR
        """)

    private static func certificate(_ base64: String) -> SecCertificate {
        // swiftlint:disable:next force_unwrapping
        let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
        // swiftlint:disable:next force_unwrapping
        return SecCertificateCreateWithData(nil, der as CFData)!
    }
}
