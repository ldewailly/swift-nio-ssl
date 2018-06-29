//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOOpenSSL

/// A reference to an OpenSSL private key object in the form of an `EVP_PKEY *`.
///
/// This thin wrapper class allows us to use ARC to automatically manage
/// the memory associated with this key. That ensures that OpenSSL
/// will not free the underlying buffer until we are done with the key.
///
/// This class also provides several convenience constructors that allow users
/// to obtain an in-memory representation of a key from a buffer of
/// bytes or from a file path.
public class OpenSSLPrivateKey {
    internal let ref: OpaquePointer

    private init(withReference ref: OpaquePointer) {
        self.ref = ref
    }

    /// Create an OpenSSLPrivateKey from a file at a given path in either PEM or
    /// DER format.
    public convenience init (file: String, format: OpenSSLSerializationFormats) throws {
        let fileObject = file.withCString { filePtr in
            return fopen(filePtr, "rb")
        }
        defer {
            fclose(fileObject)
        }

        let key: OpaquePointer?
        switch format {
        case .pem:
            key = PEM_read_PrivateKey(fileObject, nil, nil, nil).map(OpaquePointer.init)
        case .der:
            key = d2i_PrivateKey_fp(fileObject, nil).map(OpaquePointer.init)
        }

        if key == nil {
            throw NIOOpenSSLError.failedToLoadPrivateKey
        }

        self.init(withReference: key!)
    }

    /// Create an OpenSSLPrivateKey from a buffer of bytes in either PEM or
    /// DER format.
    public convenience init (buffer: [Int8], format: OpenSSLSerializationFormats) throws  {
        let bio = buffer.withUnsafeBytes {
            return BIO_new_mem_buf(UnsafeMutableRawPointer(mutating: $0.baseAddress!), Int32($0.count))!
        }
        defer {
            BIO_free(bio)
        }

        let key: OpaquePointer?
        switch format {
        case .pem:
            key = PEM_read_bio_PrivateKey(bio, nil, nil, nil).map(OpaquePointer.init)
        case .der:
            key = d2i_PrivateKey_bio(bio, nil).map(OpaquePointer.init)
        }

        if key == nil {
            throw NIOOpenSSLError.failedToLoadPrivateKey
        }

        self.init(withReference: key!)
    }

    /// Create an OpenSSLPrivateKey wrapping a pointer into OpenSSL.
    ///
    /// This is a function that should be avoided as much as possible because it plays poorly with
    /// OpenSSL's reference-counted memory. This function does not increment the reference count for the EVP_PKEY
    /// object here, nor does it duplicate it: it just takes ownership of the copy here. This object
    /// **will** deallocate the underlying EVP_PKEY object when deinited, and so if you need to keep that
    /// EVP_PKEY object alive you should call X509_dup before passing the pointer here.
    ///
    /// In general, however, this function should be avoided in favour of one of the convenience
    /// initializers, which ensure that the lifetime of the X509 object is better-managed.
    ///
    /// Please be aware that if you pass a pointer that is not to an EVP_PKEY, this method will not fail. Instead,
    /// we'll happily carry on through as though it was all good, and then crash latter. You are responsible for
    /// ensuring you pass the correct pointer type.
    static public func fromUnsafePointer<T>(pointer: UnsafePointer<T>) -> OpenSSLPrivateKey {
        return OpenSSLPrivateKey(withReference: .init(pointer))
    }

    /// Create an OpenSSLPrivateKey wrapping a pointer into OpenSSL.
    ///
    /// This is a function that should be avoided as much as possible because it plays poorly with
    /// OpenSSL's reference-counted memory. This function does not increment the reference count for the EVP_PKEY
    /// object here, nor does it duplicate it: it just takes ownership of the copy here. This object
    /// **will** deallocate the underlying EVP_PKEY object when deinited, and so if you need to keep that
    /// EVP_PKEY object alive you should call X509_dup before passing the pointer here.
    ///
    /// In general, however, this function should be avoided in favour of one of the convenience
    /// initializers, which ensure that the lifetime of the X509 object is better-managed.
    ///
    /// Please be aware that if the pointer is not to an EVP_PKEY, this method will not fail. Instead, we'll
    /// discover later when we try to use this method. You are responsible for the type safety of your code here.
    static public func fromUnsafePointer(pointer: OpaquePointer) -> OpenSSLPrivateKey {
        return OpenSSLPrivateKey(withReference: pointer)
    }

    deinit {
        EVP_PKEY_free(.init(ref))
    }
}

extension OpenSSLPrivateKey: Equatable {
    public static func ==(lhs: OpenSSLPrivateKey, rhs: OpenSSLPrivateKey) -> Bool {
        return EVP_PKEY_cmp(.init(lhs.ref), .init(rhs.ref)) != 0
    }
}
