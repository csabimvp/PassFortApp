/*
* Botan 3.13.0 Amalgamation
* (C) 1999-2023 The Botan Authors
*
* Botan is released under the Simplified BSD License (see license.txt)
*/

#ifndef BOTAN_AMALGAMATION_H_
#define BOTAN_AMALGAMATION_H_

#include <array>
#include <chrono>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <exception>
#include <initializer_list>
#include <iosfwd>
#include <memory>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

/**
* @file  build.h
* @brief Build configuration for Botan 3.13.0
*/

/* NOLINTBEGIN(*-macro-usage,*-macro-to-enum) */

/**
 * @defgroup buildinfo Build Information
 */

/**
 * @ingroup buildinfo
 * @defgroup buildinfo_version Build version information
 * @{
 */

/**
* The major version of the release
*/
#define BOTAN_VERSION_MAJOR 3

/**
* The minor version of the release
*/
#define BOTAN_VERSION_MINOR 13

/**
* The patch version of the release
*/
#define BOTAN_VERSION_PATCH 0

/**
 * Expands to an integer of the form YYYYMMDD if this is an official
 * release, or 0 otherwise. For instance, 2.19.0, which was released
 * on January 19, 2022, has a `BOTAN_VERSION_DATESTAMP` of 20220119.
 *
 * This macro is deprecated; use version_datestamp from version.h
 *
 * TODO(Botan4) remove this
 */
#define BOTAN_VERSION_DATESTAMP 0

/**
 * A string set to the release type
 *
 * This macro is deprecated
 *
 * TODO(Botan4) remove this
 */
#define BOTAN_VERSION_RELEASE_TYPE "unreleased"

/**
 * A macro expanding to a string that is set to a revision identifier
 * corresponding to the source, or "unknown" if this could not be
 * determined. It is set for all official releases.
 *
 * This macro is deprecated; use version_vc_revision from version.h
 *
 * TODO(Botan4) remove this
 */
#define BOTAN_VERSION_VC_REVISION "unknown"

/**
 * A macro expanding to a string that is set at build time using the
 * `--distribution-info` option. It allows a packager of the library
 * to specify any distribution-specific patches. If no value is given
 * at build time, the value is the string "unspecified".
 *
 * This macro is deprecated; use version_distribution_info from version.h
 *
 * TODO(Botan4) remove this
 */
#define BOTAN_DISTRIBUTION_INFO "unspecified"

/**
 * @}
 */

/**
 * @ingroup buildinfo
 * @defgroup buildinfo_configuration Build configurations
 * @{
 */




#ifndef BOTAN_DLL
  #define BOTAN_DLL 
#endif

/* Target identification and feature test macros */

#define BOTAN_TARGET_OS_HAS_FILESYSTEM
#define BOTAN_TARGET_OS_HAS_THREADS



/**
 * @}
 */

/**
 * @ingroup buildinfo
 * @defgroup buildinfo_modules Enabled modules and API versions
 * @{
 */

/*
* Module availability definitions
*/
#define BOTAN_HAS_AEAD_CHACHA20_POLY1305 20180807
#define BOTAN_HAS_AEAD_GCM 20131128
#define BOTAN_HAS_AEAD_MODES 20131128
#define BOTAN_HAS_AES 20131128
#define BOTAN_HAS_ARGON2 20210407
#define BOTAN_HAS_ARGON2_FMT 20210407
#define BOTAN_HAS_AUTO_RNG 20161126
#define BOTAN_HAS_AUTO_SEEDING_RNG 20160821
#define BOTAN_HAS_BASE32_CODEC 20180418
#define BOTAN_HAS_BASE64_CODEC 20131128
#define BOTAN_HAS_BLAKE2B 20130131
#define BOTAN_HAS_BLOCK_CIPHER 20131128
#define BOTAN_HAS_CHACHA 20180807
#define BOTAN_HAS_CIPHER_MODES 20180124
#define BOTAN_HAS_CTR_BE 20131128
#define BOTAN_HAS_HASH 20180112
#define BOTAN_HAS_HEX_CODEC 20131128
#define BOTAN_HAS_HKDF 20170927
#define BOTAN_HAS_HMAC 20131128
#define BOTAN_HAS_HMAC_DRBG 20140319
#define BOTAN_HAS_KDF 20250528
#define BOTAN_HAS_KDF_BASE 20131128
#define BOTAN_HAS_MAC 20150626
#define BOTAN_HAS_MODES 20150626
#define BOTAN_HAS_NIST_KEYWRAP 20171119
#define BOTAN_HAS_PASSWORD_HASHING 20210419
#define BOTAN_HAS_PBKDF 20180902
#define BOTAN_HAS_PBKDF2 20180902
#define BOTAN_HAS_POLY1305 20141227
#define BOTAN_HAS_RFC3394_KEYWRAP 20131128
#define BOTAN_HAS_SHA2_32 20131128
#define BOTAN_HAS_SHA2_64 20131128
#define BOTAN_HAS_SHA_224 20250130
#define BOTAN_HAS_SHA_256 20250130
#define BOTAN_HAS_SHA_384 20250130
#define BOTAN_HAS_SHA_512 20250130
#define BOTAN_HAS_SHA_512_256 20250130
#define BOTAN_HAS_STATEFUL_RNG 20160819
#define BOTAN_HAS_STREAM_CIPHER 20131128
#define BOTAN_HAS_SYSTEM_RNG 20141202


/*
* Internal module feature definitions
*
* These macros have been in the past visible in build.h as feature macros
* but in the future these will be only visible in an internal header.
* Applications should not rely on or check for these macros.
*/
#define BOTAN_HAS_AES_ARMV8 20170903
#define BOTAN_HAS_CPUID 20170917
#define BOTAN_HAS_CPUID_DETECTION 20250327
#define BOTAN_HAS_GHASH 20201002
#define BOTAN_HAS_MDX_HASH_FUNCTION 20131128
#define BOTAN_HAS_OS_UTILS 20241202


/**
 * @}
 */

/* NOLINTEND(*-macro-usage,*-macro-to-enum) */

// NOLINTBEGIN(*-macro-usage)

/**
* Used to annotate API exports which are public and supported.
* These APIs will not be broken/removed unless strictly required for
* functionality or security, and only in new major versions.
* @param maj The major version this public API was released in
* @param min The minor version this public API was released in
*/
#define BOTAN_PUBLIC_API(maj, min) BOTAN_DLL

/**
* Used to annotate API exports which are public, but are now deprecated
* and which will be removed in a future major release.
*/
#define BOTAN_DEPRECATED_API(msg) BOTAN_DEPRECATED(msg) BOTAN_DLL

/**
* Used to annotate API exports which are public and can be used by
* applications if needed, but which are intentionally not documented,
* and which may change incompatibly in a future major version.
*/
#define BOTAN_UNSTABLE_API BOTAN_DLL

/**
* Used to annotate API exports which are exported but only for the
* purposes of testing. They should not be used by applications and
* may be removed or changed without notice.
*/
#define BOTAN_TEST_API BOTAN_DLL

/**
* This is used to mark constructors which are currently not `explicit`
* but which in a future major release be modified as such.
*
* TODO(Botan4) remove this macro and replace with `explicit`
*/
#if defined(__clang_analyzer__) || defined(BOTAN_DISABLE_DEPRECATED_FEATURES)
   #define BOTAN_FUTURE_EXPLICIT explicit
#else
   #define BOTAN_FUTURE_EXPLICIT
#endif

/**
* Used to annotate API exports which are exported but only for the
* purposes of fuzzing. They should not be used by applications and
* may be removed or changed without notice.
*
* They are only exported if the fuzzers are being built
*/
#if defined(BOTAN_FUZZERS_ARE_BEING_BUILT)
   #define BOTAN_FUZZER_API BOTAN_DLL
#else
   #define BOTAN_FUZZER_API
#endif

/*
* Define BOTAN_DEPRECATED
*/
#if !defined(BOTAN_NO_DEPRECATED_WARNINGS) && !defined(BOTAN_AMALGAMATION_H_) && !defined(BOTAN_IS_BEING_BUILT)

   #define BOTAN_DEPRECATED(msg) [[deprecated(msg)]]

   #if defined(__clang__)
      #define BOTAN_DEPRECATED_HEADER(hdr) _Pragma("message \"this header is deprecated\"")
      #define BOTAN_FUTURE_INTERNAL_HEADER(hdr) _Pragma("message \"this header will be made internal in the future\"")
   #elif defined(_MSC_VER)
      #if !defined(BOTAN_STRINGIFY) && !defined(BOTAN_STRINGIFY_2)
         #define BOTAN_STRINGIFY_2(x) #x
         #define BOTAN_STRINGIFY(x) BOTAN_STRINGIFY_2(x)
      #endif
      #define BOTAN_DEPRECATED_HEADER(hdr) \
         __pragma(message(__FILE__ "(" BOTAN_STRINGIFY(__LINE__) "): this header is deprecated"))
      #define BOTAN_FUTURE_INTERNAL_HEADER(hdr) \
         __pragma(message(__FILE__ "(" BOTAN_STRINGIFY(__LINE__) "): this header will be made internal in the future"))
   #elif defined(__GNUC__)
      #define BOTAN_DEPRECATED_HEADER(hdr) _Pragma("GCC warning \"this header is deprecated\"")
      #define BOTAN_FUTURE_INTERNAL_HEADER(hdr) \
         _Pragma("GCC warning \"this header will be made internal in the future\"")
   #endif

#endif

#if !defined(BOTAN_DEPRECATED)
   #define BOTAN_DEPRECATED(msg)
#endif

#if !defined(BOTAN_DEPRECATED_HEADER)
   #define BOTAN_DEPRECATED_HEADER(hdr)
#endif

#if !defined(BOTAN_FUTURE_INTERNAL_HEADER)
   #define BOTAN_FUTURE_INTERNAL_HEADER(hdr)
#endif

#if defined(__clang__)
   #define BOTAN_DIAGNOSTIC_PUSH _Pragma("clang diagnostic push")
   #define BOTAN_DIAGNOSTIC_IGNORE_DEPRECATED_DECLARATIONS \
      _Pragma("clang diagnostic ignored \"-Wdeprecated-declarations\"")
   #define BOTAN_DIAGNOSTIC_IGNORE_INHERITED_VIA_DOMINANCE
   #define BOTAN_DIAGNOSTIC_POP _Pragma("clang diagnostic pop")
#elif defined(__GNUG__)
   #define BOTAN_DIAGNOSTIC_PUSH _Pragma("GCC diagnostic push")
   #define BOTAN_DIAGNOSTIC_IGNORE_DEPRECATED_DECLARATIONS \
      _Pragma("GCC diagnostic ignored \"-Wdeprecated-declarations\"")
   #define BOTAN_DIAGNOSTIC_IGNORE_INHERITED_VIA_DOMINANCE
   #define BOTAN_DIAGNOSTIC_POP _Pragma("GCC diagnostic pop")
#elif defined(_MSC_VER)
   #define BOTAN_DIAGNOSTIC_PUSH __pragma(warning(push))
   #define BOTAN_DIAGNOSTIC_IGNORE_DEPRECATED_DECLARATIONS __pragma(warning(disable : 4996))
   #define BOTAN_DIAGNOSTIC_IGNORE_INHERITED_VIA_DOMINANCE __pragma(warning(disable : 4250))
   #define BOTAN_DIAGNOSTIC_POP __pragma(warning(pop))
#else
   #define BOTAN_DIAGNOSTIC_PUSH
   #define BOTAN_DIAGNOSTIC_IGNORE_DEPRECATED_DECLARATIONS
   #define BOTAN_DIAGNOSTIC_IGNORE_INHERITED_VIA_DOMINANCE
   #define BOTAN_DIAGNOSTIC_POP
#endif

// NOLINTEND(*-macro-usage)

/**
* MSVC does define __cplusplus but pins it at 199711L, because "legacy".
* Note: There is a compiler switch to enable standard behavior (/Zc:__cplusplus),
*       but we can't control that in downstream applications.
*
* See: https://learn.microsoft.com/en-us/cpp/build/reference/zc-cplusplus
*/
#if defined(_MSVC_LANG)
   #define BOTAN_CPLUSPLUS _MSVC_LANG
#else
   #define BOTAN_CPLUSPLUS __cplusplus
#endif

#if BOTAN_CPLUSPLUS < 202002L
   #error "Botan 3.x requires at least C++20"
#endif

namespace Botan {

/**
* @mainpage Botan Crypto Library API Reference
*
* <dl>
* <dt>Abstract Base Classes<dd>
*        BlockCipher, HashFunction, KDF, MessageAuthenticationCode, RandomNumberGenerator,
*        StreamCipher, SymmetricAlgorithm, AEAD_Mode, Cipher_Mode, XOF
* <dt>Public Key Interface Classes<dd>
*        PK_Key_Agreement, PK_Signer, PK_Verifier, PK_Encryptor, PK_Decryptor, PK_KEM_Encryptor, PK_KEM_Decryptor
* <dt>Authenticated Encryption Modes<dd>
*        @ref Ascon_AEAD128 "Ascon-AEAD128" @ref CCM_Mode "CCM", @ref ChaCha20Poly1305_Mode "ChaCha20Poly1305",
*        @ref EAX_Mode "EAX", @ref GCM_Mode "GCM", @ref OCB_Mode "OCB", @ref SIV_Mode "SIV"
* <dt>Block Ciphers<dd>
*        @ref aria.h "ARIA", @ref aes.h "AES", @ref Blowfish, @ref camellia.h "Camellia", @ref Cascade_Cipher "Cascade",
*        @ref CAST_128 "CAST-128", @ref CAST_128 DES, @ref TripleDES "3DES",
*        @ref GOST_28147_89 "GOST 28147-89", IDEA, Kuznyechik, Lion, Noekeon, SEED, Serpent, SHACAL2, SM4,
*        @ref Threefish_512 "Threefish", Twofish
* <dt>Stream Ciphers<dd>
*        ChaCha, @ref CTR_BE "CTR", OFB, RC4, Salsa20
* <dt>Hash Functions<dd>
*        @ref Ascon_Hash256 "Ascon-Hash256", BLAKE2b, @ref GOST_34_11 "GOST 34.11", @ref Keccak_1600 "Keccak", MD4,
*        MD5, @ref RIPEMD_160 "RIPEMD-160", @ref SHA_1 "SHA-1", @ref SHA_224 "SHA-224", @ref SHA_256 "SHA-256",
*        @ref SHA_384 "SHA-384", @ref SHA_512 "SHA-512", @ref Skein_512 "Skein-512", SM3, Streebog, Whirlpool
* <dt>Non-Cryptographic Checksums<dd>
*        Adler32, CRC24, CRC32
* <dt>Message Authentication Codes<dd>
*        @ref BLAKE2bMAC "BLAKE2b", CMAC, HMAC, KMAC, Poly1305, SipHash, ANSI_X919_MAC
* <dt>Random Number Generators<dd>
*        AutoSeeded_RNG, HMAC_DRBG, Processor_RNG, System_RNG
* <dt>Key Derivation<dd>
*        HKDF, @ref KDF1 "KDF1 (IEEE 1363)", @ref KDF1_18033 "KDF1 (ISO 18033-2)", @ref KDF2 "KDF2 (IEEE 1363)",
*        @ref sp800_108.h "SP800-108", @ref SP800_56C "SP800-56C", @ref PKCS5_PBKDF2 "PBKDF2 (PKCS#5)"
* <dt>Password Hashing<dd>
*        @ref argon2.h "Argon2", @ref scrypt.h "scrypt", @ref bcrypt.h "bcrypt", @ref passhash9.h "passhash9"
* <dt>Public Key Cryptosystems<dd>
*        @ref dlies.h "DLIES", @ref ecies.h "ECIES", @ref elgamal.h "ElGamal",
*        @ref rsa.h "RSA", @ref mceliece.h "McEliece", @ref sm2.h "SM2"
* <dt>Key Encapsulation Mechanisms<dd>
*        @ref cmce.h "Classic McEliece", @ref frodokem.h "FrodoKEM", @ref kyber.h "ML-KEM/Kyber", @ref rsa.h "RSA"
* <dt>Public Key Signature Schemes<dd>
*        @ref dsa.h "DSA", @ref dilithium.h "ML-DSA/Dilithium", @ref ecdsa.h "ECDSA", @ref ecgdsa.h "ECGDSA",
*        @ref eckcdsa.h "ECKCDSA", @ref gost_3410.h "GOST 34.10-2001", @ref hss_lms.h "HSS/LMS", @ref sm2.h "SM2",
         @ref sphincsplus.h "SLH-DSA/SPHINCS+", @ref xmss.h "XMSS"
* <dt>Key Agreement<dd>
*        @ref dh.h "DH", @ref ecdh.h "ECDH"
* <dt>Compression<dd>
*        @ref bzip2.h "bzip2", @ref lzma.h "lzma", @ref zlib.h "zlib"
* <dt>TLS<dd>
*        TLS::Client, TLS::Server, TLS::Policy, TLS::Protocol_Version, TLS::Callbacks, TLS::Ciphersuite,
*        TLS::Session, TLS::Session_Summary, TLS::Session_Manager, Credentials_Manager
* <dt>X.509<dd>
*        X509_Certificate, X509_CRL, X509_CA, Certificate_Extension, PKCS10_Request, X509_Cert_Options,
*        Certificate_Store, Certificate_Store_In_SQL, Certificate_Store_In_SQLite
* <dt>eXtendable Output Functions<dd>
*        @ref Ascon_XOF128 "Ascon-XOF128", @ref SHAKE_XOF "SHAKE"
* </dl>
*/

using std::int32_t;
using std::int64_t;
using std::size_t;
using std::uint16_t;
using std::uint32_t;
using std::uint64_t;
using std::uint8_t;

#if !defined(BOTAN_IS_BEING_BUILT)
/*
* These typedefs are no longer used within the library headers
* or code. They are kept only for compatibility with software
* written against older versions.
*/

/// Unsigned 8 bit integer; retained for compatibility with older versions
using byte = std::uint8_t;

/// Unsigned 16 bit integer; retained for compatibility with older versions
using u16bit = std::uint16_t;

/// Unsigned 32 bit integer; retained for compatibility with older versions
using u32bit = std::uint32_t;

/// Unsigned 64 bit integer; retained for compatibility with older versions
using u64bit = std::uint64_t;

/// Signed 32 bit integer; retained for compatibility with older versions
using s32bit = std::int32_t;
#endif

/// True if this target has native 64 bit registers
static constexpr bool HasNative64BitRegisters = sizeof(void*) >= 8;

/// The native machine word, used as the limb type for multiprecision integers
using word = std::conditional_t<HasNative64BitRegisters, std::uint64_t, uint32_t>;

#if defined(__SIZEOF_INT128__)
   #define BOTAN_TARGET_HAS_NATIVE_UINT128

/// Unsigned 128 bit integer, only available if the compiler supports it
// GCC complains if this isn't marked with __extension__
__extension__ typedef unsigned __int128 uint128_t;
#endif

/*
* Should this assert fail on your system please contact the developers
* for assistance in porting.
*/
static_assert(sizeof(std::size_t) == 8 || sizeof(std::size_t) == 4, "This platform has an unexpected size for size_t");

/**
* How much to allocate for a buffer of no particular size
*/
constexpr size_t DefaultBufferSize = 4096;

}  // namespace Botan

namespace Botan {

/**
 * Trait that checks whether all of the given types are the same type
 */
template <typename T0 = void, typename... Ts>
struct all_same {
      /// True if every type in Ts is the same as T0
      static constexpr bool value = (std::is_same_v<T0, Ts> && ... && true);
};

template <typename... Ts>
static constexpr bool all_same_v = all_same<Ts...>::value;

namespace detail {

/**
 * Helper type to indicate that a certain type should be automatically
 * detected based on the context.
 */
struct AutoDetect {
      /// This type is a tag only and cannot be instantiated
      constexpr AutoDetect() = delete;
};

}  // namespace detail

namespace concepts {

// TODO: C++20 provides concepts like std::ranges::range or ::sized_range
//       but at the time of this writing clang had not caught up on all
//       platforms. E.g. clang 14 on Xcode does not support ranges properly.

template <typename IterT, typename ContainerT>
concept container_iterator =
   std::same_as<IterT, typename ContainerT::iterator> || std::same_as<IterT, typename ContainerT::const_iterator>;

template <typename PtrT, typename ContainerT>
concept container_pointer =
   std::same_as<PtrT, typename ContainerT::pointer> || std::same_as<PtrT, typename ContainerT::const_pointer>;

template <typename T>
concept container = requires(T a) {
   { a.begin() } -> container_iterator<T>;
   { a.end() } -> container_iterator<T>;
   { a.cbegin() } -> container_iterator<T>;
   { a.cend() } -> container_iterator<T>;
   { a.size() } -> std::same_as<typename T::size_type>;
   typename T::value_type;
};

template <typename T>
concept contiguous_container = container<T> && requires(T a) {
   { a.data() } -> container_pointer<T>;
};

template <typename T>
concept has_empty = requires(T a) {
   { a.empty() } -> std::same_as<bool>;
};

template <typename T>
concept resizable_container = container<T> && requires(T& c, typename T::size_type s) {
   T(s);
   c.resize(s);
};

template <typename T>
concept reservable_container = container<T> && requires(T& c, typename T::size_type s) { c.reserve(s); };

template <typename T>
concept resizable_byte_buffer =
   contiguous_container<T> && resizable_container<T> && std::same_as<typename T::value_type, uint8_t>;

}  // namespace concepts

}  // namespace Botan

namespace Botan {

/*
* Define BOTAN_MALLOC_FN
*/
#if defined(__clang__) || defined(__GNUG__)
   #define BOTAN_MALLOC_FN __attribute__((malloc))
#elif defined(_MSC_VER)
   #define BOTAN_MALLOC_FN __declspec(restrict)
#else
   #define BOTAN_MALLOC_FN
#endif

/**
* Allocate a memory buffer by some method. This should only be used for
* primitive types (uint8_t, uint32_t, etc).
*
* @param elems the number of elements
* @param elem_size the size of each element
* @return pointer to allocated and zeroed memory, or throw std::bad_alloc on failure
*/
BOTAN_PUBLIC_API(2, 3) BOTAN_MALLOC_FN void* allocate_memory(size_t elems, size_t elem_size);

/**
* Free a pointer returned by allocate_memory
* @param p the pointer returned by allocate_memory
* @param elems the number of elements, as passed to allocate_memory
* @param elem_size the size of each element, as passed to allocate_memory
*/
BOTAN_PUBLIC_API(2, 3) void deallocate_memory(void* p, size_t elems, size_t elem_size);

/**
* Ensure the allocator is initialized
*/
void BOTAN_UNSTABLE_API initialize_allocator();

/**
* Initializes the allocator as a side effect of construction
*
* Declare a static instance in a translation unit to ensure the allocator
* is initialized before any other static initialization in that unit.
*/
class Allocator_Initializer final {
   public:
      /// Initialize the allocator
      Allocator_Initializer() { initialize_allocator(); }
};

}  // namespace Botan

#if !defined(BOTAN_IS_BEING_BUILT) && !defined(BOTAN_DISABLE_DEPRECATED_FEATURES)
   // TODO(Botan4) remove this
   #include <deque>
#endif

namespace Botan {

template <typename T>
#if !defined(_ITERATOR_DEBUG_LEVEL) || _ITERATOR_DEBUG_LEVEL == 0
/*
 * Check exists to prevent someone from doing something that will
 * probably crash anyway (like secure_vector<non_POD_t> where ~non_POD_t
 * deletes a member pointer which was zeroed before it ran).
 * MSVC in debug mode uses non-integral proxy types in container types
 * like std::vector, thus we disable the check there.
 */
   requires std::is_integral_v<T> || std::is_enum_v<T>
#endif

/**
* An allocator which zeroizes memory before releasing it
*
* Restricted to integral and enum types, since a non-trivial destructor
* would run after the object had already been zeroized.
*/
class secure_allocator {

   public:
      /**
      * The type being allocated
      */
      typedef T value_type;

      /**
      * The type used to express allocation sizes
      */
      typedef std::size_t size_type;

      /**
      * Default constructor
      */
      secure_allocator() noexcept = default;

      /**
      * Copy constructor
      */
      secure_allocator(const secure_allocator&) noexcept = default;

      /**
      * Copy assignment
      * @return reference to this
      */
      secure_allocator& operator=(const secure_allocator&) noexcept = default;

      /**
      * Move constructor
      */
      secure_allocator(secure_allocator&&) noexcept = default;

      /**
      * Move assignment
      * @return reference to this
      */
      secure_allocator& operator=(secure_allocator&&) noexcept = default;

      ~secure_allocator() noexcept = default;

      /**
      * Convert an allocator for a different type
      */
      template <typename U>
      explicit secure_allocator(const secure_allocator<U>& /*other*/) noexcept {}

      /**
      * Allocate storage for n objects
      * @param n the number of objects
      * @return a pointer to the allocated storage
      */
      T* allocate(std::size_t n) { return static_cast<T*>(allocate_memory(n, sizeof(T))); }

      /**
      * Zeroize and release storage previously returned by allocate
      * @param p the pointer to release
      * @param n the number of objects p was allocated for
      */
      void deallocate(T* p, std::size_t n) { deallocate_memory(p, n, sizeof(T)); }
};

/**
* Compare two secure allocators
*
* All instances are interchangeable, so this is always true.
* @return always true
*/
template <typename T, typename U>
inline bool operator==(const secure_allocator<T>& /*a*/, const secure_allocator<U>& /*b*/) {
   return true;
}

/**
* Compare two secure allocators
*
* All instances are interchangeable, so this is always false.
* @return always false
*/
template <typename T, typename U>
inline bool operator!=(const secure_allocator<T>& /*a*/, const secure_allocator<U>& /*b*/) {
   return false;
}

template <typename T>
using secure_vector = std::vector<T, secure_allocator<T>>;

#if !defined(BOTAN_IS_BEING_BUILT) && !defined(BOTAN_DISABLE_DEPRECATED_FEATURES)
template <typename T>
using secure_deque = std::deque<T, secure_allocator<T>>;
#endif

// For better compatibility with 1.10 API
template <typename T>
using SecureVector = secure_vector<T>;

/**
* Copy a vector into a secure_vector
* @param in the vector to copy
* @return a secure_vector holding the same contents
*/
template <typename T>
secure_vector<T> lock(const std::vector<T>& in) {
   return secure_vector<T>(in.begin(), in.end());
}

/**
* Copy a secure_vector into an ordinary vector
* @param in the vector to copy
* @return a std::vector holding the same contents
*/
template <typename T>
std::vector<T> unlock(const secure_vector<T>& in) {
   return std::vector<T>(in.begin(), in.end());
}

// TODO(Botan4) remove these += operators entirely

/**
* Append the contents of one vector to another
* @param out the vector to append to
* @param in the vector to append
* @return reference to out
*/
template <typename T, typename Alloc, typename Alloc2>
std::vector<T, Alloc>& operator+=(std::vector<T, Alloc>& out, const std::vector<T, Alloc2>& in) {
   out.insert(out.end(), in.begin(), in.end());
   return out;
}

/**
* Append the contents of a span to a vector
* @param out the vector to append to
* @param in the elements to append
* @return reference to out
*/
template <typename T, typename Alloc>
std::vector<T, Alloc>& operator+=(std::vector<T, Alloc>& out, std::span<const T> in) {
   out.insert(out.end(), in.begin(), in.end());
   return out;
}

/**
* Append a single element to a vector
* @param out the vector to append to
* @param in the element to append
* @return reference to out
*/
template <typename T, typename Alloc>
std::vector<T, Alloc>& operator+=(std::vector<T, Alloc>& out, T in) {
   out.push_back(in);
   return out;
}

/**
* Append a (pointer, length) pair to a vector
* @param out the vector to append to
* @param in the elements to append
* @return reference to out
*/
template <typename T, typename Alloc, typename L>
std::vector<T, Alloc>& operator+=(std::vector<T, Alloc>& out, const std::pair<const T*, L>& in) {
   if(in.second > 0) {
      out.insert(out.end(), in.first, in.first + in.second);
   }
   return out;
}

/**
* Append a (pointer, length) pair to a vector
* @param out the vector to append to
* @param in the elements to append
* @return reference to out
*/
template <typename T, typename Alloc, typename L>
std::vector<T, Alloc>& operator+=(std::vector<T, Alloc>& out, const std::pair<T*, L>& in) {
   if(in.second > 0) {
      out.insert(out.end(), in.first, in.first + in.second);
   }
   return out;
}

/**
* Zeroise the values; length remains unchanged
*
* Note this is not intended for cases where the compiler might elide
* the writes as being without side-effects; use secure_scrub_memory
* for that.
*
* TODO(Botan4): make these not-inlined and only for secure_vector, eg declare
*  void zeroize(secure_vector<uint8_t>& v);
*  void zeroize(secure_vector<uint16_t>& v);
*  void zeroize(secure_vector<uint32_t>& v);
*  void zeroize(secure_vector<uint64_t>& v);
*
* @param vec the vector to zeroise
*/
template <typename T, typename Alloc>
void zeroise(std::vector<T, Alloc>& vec) {
   for(size_t i = 0; i != vec.size(); ++i) {
      vec[i] = static_cast<T>(0);
   }
}

/**
* Zeroise the values then free the memory
*
* TODO(Botan4): make these not-inlined and only for secure_vector, eg declare
*  void zap(secure_vector<uint8_t>& v);
*  void zap(secure_vector<uint16_t>& v);
*  void zap(secure_vector<uint32_t>& v);
*  void zap(secure_vector<uint64_t>& v);
*
* [And maybe rename as well]
*
* @param vec the vector to zeroise and free
*/
template <typename T, typename Alloc>
void zap(std::vector<T, Alloc>& vec) {
   zeroise(vec);
   vec.clear();
   vec.shrink_to_fit();
}

}  // namespace Botan

namespace Botan {

class OctetString;

/**
* Represents the length requirements on an algorithm key
*/
class BOTAN_PUBLIC_API(2, 0) Key_Length_Specification final {
   public:
      /**
      * Constructor for fixed length keys
      * @param keylen the supported key length
      */
      explicit Key_Length_Specification(size_t keylen) : m_min_keylen(keylen), m_max_keylen(keylen), m_keylen_mod(1) {}

      /**
      * Constructor for variable length keys
      * @param min_k the smallest supported key length
      * @param max_k the largest supported key length
      * @param k_mod the number of bytes the key must be a multiple of
      */
      Key_Length_Specification(size_t min_k, size_t max_k, size_t k_mod = 1) :
            m_min_keylen(min_k), m_max_keylen(max_k > 0 ? max_k : min_k), m_keylen_mod(k_mod) {}

      /**
      * Test if a key length is acceptable
      * @param length is a key length in bytes
      * @return true iff this length is a valid length for this algo
      */
      bool valid_keylength(size_t length) const {
         return ((length >= m_min_keylen) && (length <= m_max_keylen) && (length % m_keylen_mod == 0));
      }

      /**
      * Return the smallest acceptable key length
      * @return minimum key length in bytes
      */
      size_t minimum_keylength() const { return m_min_keylen; }

      /**
      * Return the largest acceptable key length
      * @return maximum key length in bytes
      */
      size_t maximum_keylength() const { return m_max_keylen; }

      /**
      * Return the granularity of acceptable key lengths
      * @return key length multiple in bytes
      */
      size_t keylength_multiple() const { return m_keylen_mod; }

      /**
      * Scale all length requirements by a factor
      * Multiplies all length requirements with the given factor
      * @param n the multiplication factor
      * @return a key length specification multiplied by the factor
      */
      Key_Length_Specification multiple(size_t n) const {
         return Key_Length_Specification(n * m_min_keylen, n * m_max_keylen, n * m_keylen_mod);
      }

   private:
      size_t m_min_keylen, m_max_keylen, m_keylen_mod;
};

/**
* This class represents a symmetric algorithm object.
*/
class BOTAN_PUBLIC_API(2, 0) SymmetricAlgorithm {
   public:
      /**
      * Default constructor
      */
      SymmetricAlgorithm() = default;

      virtual ~SymmetricAlgorithm() = default;

      /**
      * Copy constructor
      */
      SymmetricAlgorithm(const SymmetricAlgorithm& other) = default;

      /**
      * Move constructor
      */
      SymmetricAlgorithm(SymmetricAlgorithm&& other) = default;

      /**
      * Copy assignment
      * @return reference to this
      */
      SymmetricAlgorithm& operator=(const SymmetricAlgorithm& other) = default;

      /**
      * Move assignment
      * @return reference to this
      */
      SymmetricAlgorithm& operator=(SymmetricAlgorithm&& other) = default;

      /**
      * Reset the internal state. This includes not just the key, but
      * any partial message that may have been in process.
      */
      virtual void clear() = 0;

      /**
      * Return the key lengths supported by this algorithm
      * @return object describing limits on key size
      */
      virtual Key_Length_Specification key_spec() const = 0;

      /**
      * Return the largest acceptable key length
      * @return maximum allowed key length
      */
      size_t maximum_keylength() const { return key_spec().maximum_keylength(); }

      /**
      * Return the smallest acceptable key length
      * @return minimum allowed key length
      */
      size_t minimum_keylength() const { return key_spec().minimum_keylength(); }

      /**
      * Check whether a given key length is valid for this algorithm.
      * @param length the key length to be checked.
      * @return true if the key length is valid.
      */
      bool valid_keylength(size_t length) const { return key_spec().valid_keylength(length); }

      /**
      * Set the symmetric key of this object.
      * @param key the SymmetricKey to be set.
      */
      void set_key(const OctetString& key);

      /**
      * Set the symmetric key of this object.
      * @param key the contiguous byte range to be set.
      */
      void set_key(std::span<const uint8_t> key);

      /**
      * Set the symmetric key of this object.
      * @param key the to be set as a byte array.
      * @param length in bytes of key param
      */
      void set_key(const uint8_t key[], size_t length) { set_key(std::span{key, length}); }

      /**
      * Return the name of this algorithm
      * @return the algorithm name
      */
      virtual std::string name() const = 0;

      /**
      * Test whether a key has been set on this object
      * @return true if a key has been set on this object
      */
      virtual bool has_keying_material() const = 0;

   protected:
      /**
      * Throw Key_Not_Set unless a key has been set on this object
      */
      void assert_key_material_set() const { assert_key_material_set(has_keying_material()); }

      /**
      * Throw Key_Not_Set unless the predicate holds
      * @param predicate if false, a Key_Not_Set exception is thrown
      */
      void assert_key_material_set(bool predicate) const {
         if(!predicate) {
            throw_key_not_set_error();
         }
      }

   private:
      void throw_key_not_set_error() const;

      /**
      * Run the key schedule
      * @param key the key
      */
      virtual void key_schedule(std::span<const uint8_t> key) = 0;
};

}  // namespace Botan

namespace Botan {

/**
* The two possible directions a Cipher_Mode can operate in
*/
enum class Cipher_Dir : uint8_t {
   Encryption = 0,
   Decryption = 1,

   ENCRYPTION BOTAN_DEPRECATED("Use Cipher_Dir::Encryption") = Encryption,
   DECRYPTION BOTAN_DEPRECATED("Use Cipher_Dir::Decryption") = Decryption,
};

/**
* Interface for cipher modes
*/
class BOTAN_PUBLIC_API(2, 0) Cipher_Mode : public SymmetricAlgorithm {
   public:
      /**
      * List the providers available for a given cipher mode
      * @return list of available providers for this algorithm, empty if not available
      * @param algo_spec algorithm name
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Create an AEAD mode
      * @param algo the algorithm to create
      * @param direction specify if this should be an encryption or decryption AEAD
      * @param provider optional specification for provider to use
      * @return an AEAD mode or a null pointer if not available
      */
      static std::unique_ptr<Cipher_Mode> create(std::string_view algo,
                                                 Cipher_Dir direction,
                                                 std::string_view provider = "");

      /**
      * Create an AEAD mode, or throw
      * @param algo the algorithm to create
      * @param direction specify if this should be an encryption or decryption AEAD
      * @param provider optional specification for provider to use
      * @return an AEAD mode, or throw an exception
      */
      static std::unique_ptr<Cipher_Mode> create_or_throw(std::string_view algo,
                                                          Cipher_Dir direction,
                                                          std::string_view provider = "");

   protected:
      /**
      * Prepare for processing a message under the specified nonce
      */
      virtual void start_msg(const uint8_t nonce[], size_t nonce_len) = 0;

      /**
      * Process message blocks
      * Input must be a multiple of update_granularity.
      */
      virtual size_t process_msg(uint8_t msg[], size_t msg_len) = 0;

      /**
      * Finish processing a message
      */
      virtual void finish_msg(secure_vector<uint8_t>& final_block, size_t offset = 0) = 0;

   public:
      /**
      * Begin processing a message with a fresh nonce.
      *
      * @warning Typically one must not reuse the same nonce for more than one
      *          message under the same key. For most cipher modes this would
      *          mean total loss of security and/or authenticity guarantees.
      *
      * @note If reliably generating unique nonces is difficult in your
      *       environment, use SIV which retains security even if nonces
      *       are repeated.
      *
      * @param nonce the per message nonce
      */
      void start(std::span<const uint8_t> nonce) { start_msg(nonce.data(), nonce.size()); }

      /**
      * Begin processing a message with a fresh nonce.
      * @param nonce the per message nonce
      * @param nonce_len length of nonce
      */
      void start(const uint8_t nonce[], size_t nonce_len) { start_msg(nonce, nonce_len); }

      /**
      * Begin processing a message.
      *
      * The exact semantics of this depend on the mode. For many modes, the call
      * will fail since a nonce must be provided.
      *
      * For certain modes such as CBC this will instead cause the last
      * ciphertext block to be used as the nonce of the new message; doing this
      * isn't a good idea, but some (mostly older) protocols do this.
      */
      void start() { return start_msg(nullptr, 0); }

      /**
      * Process message blocks
      *
      * Input must be a multiple of update_granularity
      *
      * Processes msg in place and returns bytes written. Normally
      * this will be either msg_len (indicating the entire message was
      * processed) or for certain AEAD modes zero (indicating that the
      * mode requires the entire message be processed in one pass).
      *
      * @param msg the message to be processed
      * @return bytes written in-place
      */
      size_t process(std::span<uint8_t> msg) { return this->process_msg(msg.data(), msg.size()); }

      /**
      * Process message blocks in place
      * @param msg the message to be processed
      * @param msg_len length of msg in bytes
      * @return bytes written in-place
      */
      size_t process(uint8_t msg[], size_t msg_len) { return this->process_msg(msg, msg_len); }

      /**
      * Process some data. Input must be in size update_granularity() uint8_t
      * blocks. The @p buffer is an in/out parameter and may be resized. In
      * particular, some modes require that all input be consumed before any
      * output is produced; with these modes, @p buffer will be returned empty.
      *
      * The first @p offset bytes of @p buffer will be ignored (this allows in
      * place processing of a buffer that contains an initial plaintext header).
      *
      * @param buffer in/out parameter which will possibly be resized
      * @param offset an offset into blocks to begin processing
      */
      template <concepts::resizable_byte_buffer T>
      void update(T& buffer, size_t offset = 0) {
         const size_t written = process(std::span(buffer).subspan(offset));
         buffer.resize(offset + written);
      }

      /**
      * Complete procession of a message with a final input of @p buffer, which
      * is treated the same as with update(). If you have the entire message in
      * hand, calling finish() without ever calling update() is both efficient
      * and convenient.
      *
      * When using an AEAD_Mode, if the supplied authentication tag does not
      * validate, this will throw an instance of Invalid_Authentication_Tag.
      *
      * If this occurs, all plaintext previously output via calls to update must
      * be destroyed and not used in any way that an attacker could observe the
      * effects of. This could be anything from echoing the plaintext back
      * (perhaps in an error message), or by making an external RPC whose
      * destination or contents depend on the plaintext. The only thing you can
      * do is buffer it, and in the event of an invalid tag, erase the
      * previously decrypted content from memory.
      *
      * One simple way to assure this could never happen is to never call
      * update, and instead always marshal the entire message into a single
      * buffer and call finish on it when decrypting.
      *
      * @param final_block in/out parameter which must be at least
      *        minimum_final_size() bytes, and will be set to any final output
      * @param offset an offset into final_block to begin processing
      */
      void finish(secure_vector<uint8_t>& final_block, size_t offset = 0) { finish_msg(final_block, offset); }

      /**
      * Complete procession of a message.
      *
      * Note: Using this overload with anything but a Botan::secure_vector<>
      *       is copying the bytes in the in/out buffer.
      *
      * @param final_block in/out parameter which must be at least
      *        minimum_final_size() bytes, and will be set to any final output
      * @param offset an offset into final_block to begin processing
      */
      template <concepts::resizable_byte_buffer T>
      void finish(T& final_block, size_t offset = 0) {
         Botan::secure_vector<uint8_t> tmp(final_block.begin(), final_block.end());
         finish_msg(tmp, offset);
         final_block.resize(tmp.size());
         std::copy(tmp.begin(), tmp.end(), final_block.begin());
      }

      /**
      * Returns the size of the output if this transform is used to process a
      * message with input_length bytes. In most cases the answer is precise.
      * If it is not possible to precise (namely for CBC decryption) instead an
      * upper bound is returned.
      */
      virtual size_t output_length(size_t input_length) const = 0;

      /**
      * The :cpp:class:`Cipher_Mode` interface requires message processing in
      * multiples of the block size. This returns size of required blocks to
      * update. If the mode implementation does not require buffering it will
      * return 1.
      * @return size of required blocks to update
      */
      virtual size_t update_granularity() const = 0;

      /**
      * Return an ideal granularity. This will be a multiple of the result of
      * update_granularity but may be larger. If so it indicates that better
      * performance may be achieved by providing buffers that are at least that
      * size (due to SIMD execution, etc).
      */
      virtual size_t ideal_granularity() const = 0;

      /**
      * Certain modes require the entire message be available before
      * any processing can occur. For such modes, input will be consumed
      * but not returned, until `finish` is called, which returns the
      * entire message.
      *
      * This function returns true if this mode has this style of
      * operation.
      */
      virtual bool requires_entire_message() const { return false; }

      /**
      * Return the smallest input accepted by finish()
      * @return required minimum size to finalize() - may be any
      *         length larger than this.
      */
      virtual size_t minimum_final_size() const = 0;

      /**
      * Return the default nonce length for this mode
      * @return the default size for a nonce
      */
      virtual size_t default_nonce_length() const = 0;

      /**
      * Test if a nonce length is valid for this mode
      * @return true iff nonce_len is a valid length for the nonce
      */
      virtual bool valid_nonce_length(size_t nonce_len) const = 0;

      /**
      * Resets just the message specific state and allows encrypting again under the existing key
      */
      virtual void reset() = 0;

      /**
      * Return the length in bytes of the authentication tag this algorithm
      * generates. If the mode is not authenticated, this will return 0.
      *
      * @return true iff this mode provides authentication as well as
      *         confidentiality.
      */
      bool authenticated() const { return this->tag_size() > 0; }

      /**
      * Return the authentication tag length of this mode
      * @return the size of the authentication tag used (in bytes)
      */
      virtual size_t tag_size() const { return 0; }

      /**
      * Return the name of the provider implementing this object
      * @return provider information about this implementation. Default is "base",
      * might also return "sse2", "avx2", "openssl", or some other arbitrary string.
      */
      virtual std::string provider() const { return "base"; }
};

/**
* Get a cipher mode by name (eg "AES-128/CBC" or "Serpent/XTS")
* @param algo_spec cipher name
* @param direction Cipher_Dir::Encryption or Cipher_Dir::Decryption
* @param provider provider implementation to choose
*/
BOTAN_DEPRECATED("Use Cipher_Mode::create")
inline Cipher_Mode* get_cipher_mode(std::string_view algo_spec, Cipher_Dir direction, std::string_view provider = "") {
   return Cipher_Mode::create(algo_spec, direction, provider).release();
}

}  // namespace Botan


namespace Botan {

/**
* Interface for AEAD (Authenticated Encryption with Associated Data)
* modes. These modes provide both encryption and message
* authentication, and can authenticate additional per-message data
* which is not included in the ciphertext (for instance a sequence
* number).
*/
class BOTAN_PUBLIC_API(2, 0) AEAD_Mode : public Cipher_Mode {
   public:
      /**
      * Create an AEAD mode
      * @param algo the algorithm to create
      * @param direction specify if this should be an encryption or decryption AEAD
      * @param provider optional specification for provider to use
      * @return an AEAD mode or a null pointer if not available
      */
      static std::unique_ptr<AEAD_Mode> create(std::string_view algo,
                                               Cipher_Dir direction,
                                               std::string_view provider = "");

      /**
      * Create an AEAD mode, or throw
      * @param algo the algorithm to create
      * @param direction specify if this should be an encryption or decryption AEAD
      * @param provider optional specification for provider to use
      * @return an AEAD mode, or throw an exception
      */
      static std::unique_ptr<AEAD_Mode> create_or_throw(std::string_view algo,
                                                        Cipher_Dir direction,
                                                        std::string_view provider = "");

      /**
      * Set associated data that is not included in the ciphertext but that
      * should be authenticated. Must be called after set_key() and before
      * start().
      *
      * Unless reset by another call, the associated data is kept between
      * messages. Thus, if the AD does not change, calling once (after
      * set_key()) is the optimum.
      *
      * @param ad the associated data
      */
      void set_associated_data(std::span<const uint8_t> ad) { set_associated_data_n(0, ad); }

      /**
      * Set associated data that is not included in the ciphertext but
      * that should be authenticated. Must be called after set_key() and
      * before start().
      *
      * @param ad the associated data
      * @param ad_len length of ad in bytes
      */
      void set_associated_data(const uint8_t ad[], size_t ad_len) { set_associated_data(std::span(ad, ad_len)); }

      /**
      * Set associated data that is not included in the ciphertext but
      * that should be authenticated. Must be called after set_key() and
      * before start().
      *
      * Unless reset by another call, the associated data is kept
      * between messages. Thus, if the AD does not change, calling
      * once (after set_key()) is the optimum.
      *
      * Some AEADs (namely SIV) support multiple AD inputs. For
      * all other modes only nominal AD input 0 is supported; all
      * other values of idx will cause an exception.
      *
      * Derived AEADs must implement this. For AEADs where
      * `maximum_associated_data_inputs()` returns 1 (the default), the
      * @p idx must simply be ignored.
      *
      * @param idx which associated data to set
      * @param ad the associated data
      */
      virtual void set_associated_data_n(size_t idx, std::span<const uint8_t> ad) = 0;

      /**
      * Returns the maximum supported number of associated data inputs which
      * can be provided to set_associated_data_n
      *
      * If returns 0, then no associated data is supported.
      */
      virtual size_t maximum_associated_data_inputs() const { return 1; }

      /**
      * Most AEADs require the key to be set prior to setting the AD
      * A few allow the AD to be set even before the cipher is keyed.
      * Such ciphers would return false from this function.
      */
      virtual bool associated_data_requires_key() const { return true; }

      /**
      * Set associated data that is not included in the ciphertext but
      * that should be authenticated. Must be called after set_key() and
      * before start().
      *
      * See @ref set_associated_data().
      *
      * @param ad the associated data
      */
      template <typename Alloc>
      BOTAN_DEPRECATED("Simply use set_associated_data")
      void set_associated_data_vec(const std::vector<uint8_t, Alloc>& ad) {
         set_associated_data(ad);
      }

      /**
      * Set associated data that is not included in the ciphertext but
      * that should be authenticated. Must be called after set_key() and
      * before start().
      *
      * See @ref set_associated_data().
      *
      * @param ad the associated data
      */
      BOTAN_DEPRECATED("Use set_associated_data") void set_ad(std::span<const uint8_t> ad) { set_associated_data(ad); }

      /**
      * Return the default nonce length for this mode
      * @return default AEAD nonce size (a commonly supported value among AEAD
      * modes, and large enough that random collisions are unlikely)
      */
      size_t default_nonce_length() const override { return 12; }
};

/**
* Get an AEAD mode by name (eg "AES-128/GCM" or "Serpent/EAX")
* @param name AEAD name
* @param direction Cipher_Dir::Encryption or Cipher_Dir::Decryption
*/
BOTAN_DEPRECATED("Use AEAD_Mode::create") inline AEAD_Mode* get_aead(std::string_view name, Cipher_Dir direction) {
   return AEAD_Mode::create(name, direction, "").release();
}

}  // namespace Botan

namespace Botan {

/**
* Different types of errors that might occur
*/
enum class ErrorType : uint16_t {
   /** Some unknown error */
   Unknown = 1,
   /** An error while calling a system interface */
   SystemError = 2,
   /** An operation seems valid, but not supported by the current version */
   NotImplemented = 3,
   /** Memory allocation failure */
   OutOfMemory = 4,
   /** An internal error occurred */
   InternalError = 5,
   /** An I/O error occurred */
   IoError = 6,

   /** Invalid object state */
   InvalidObjectState = 100,
   /** A key was not set on an object when this is required */
   KeyNotSet = 101,
   /** The application provided an argument which is invalid */
   InvalidArgument = 102,
   /** A key with invalid length was provided */
   InvalidKeyLength = 103,
   /** A nonce with invalid length was provided */
   InvalidNonceLength = 104,
   /** An object type was requested but cannot be found */
   LookupError = 105,
   /** Encoding a message or datum failed */
   EncodingFailure = 106,
   /** Decoding a message or datum failed */
   DecodingFailure = 107,
   /** A TLS error (error_code will be the alert type) */
   TLSError = 108,
   /** An error during an HTTP operation */
   HttpError = 109,
   /** A message with an invalid authentication tag was detected */
   InvalidTag = 110,
   /** An error during Roughtime validation */
   RoughtimeError = 111,

   /** An error when interacting with CommonCrypto API */
   CommonCryptoError = 201,
   /** An error when interacting with a PKCS11 device */
   Pkcs11Error = 202,
   /** An error when interacting with a TPM device */
   TPMError = 203,
   /** An error when interacting with a database */
   DatabaseError = 204,

   /** An error when interacting with zlib */
   ZlibError = 300,
   /** An error when interacting with bzip2 */
   Bzip2Error = 301,
   /** An error when interacting with lzma */
   LzmaError = 302,

};

//! \brief Convert an ErrorType to string
std::string BOTAN_PUBLIC_API(2, 11) to_string(ErrorType type);

/**
* Base class for all exceptions thrown by the library
*/
class BOTAN_PUBLIC_API(2, 0) Exception : public std::exception {
   public:
      /**
      * Return a descriptive string which is hopefully comprehensible to
      * a developer. It will likely not be useful for an end user.
      *
      * The string has no particular format, and the content of exception
      * messages may change from release to release. Thus the main use of this
      * function is for logging or debugging.
      */
      const char* what() const noexcept override { return m_msg.c_str(); }

      /**
      * Return the "type" of error which occurred.
      */
      virtual ErrorType error_type() const noexcept { return ErrorType::Unknown; }

      /**
      * Return an error code associated with this exception, or otherwise 0.
      *
      * The domain of this error varies depending on the source, for example on
      * POSIX systems it might be errno, while on a Windows system it might be
      * the result of GetLastError or WSAGetLastError.
      */
      virtual int error_code() const noexcept { return 0; }

      /**
      * Avoid throwing base Exception, use a subclass
      */
      explicit Exception(std::string_view msg);

      /**
      * Avoid throwing base Exception, use a subclass
      */
      Exception(const char* prefix, std::string_view msg);

      /**
      * Avoid throwing base Exception, use a subclass
      */
      Exception(std::string_view msg, const std::exception& e);

   private:
      std::string m_msg;
};

/**
* An invalid argument was provided to an API call.
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_Argument : public Exception {
   public:
      /**
      * Create a Invalid_Argument exception
      * @param msg a description of the problem
      */
      explicit Invalid_Argument(std::string_view msg);

      /**
      * Create a Invalid_Argument exception
      * @param msg a description of the problem
      * @param where the API call which received the invalid argument
      */
      explicit Invalid_Argument(std::string_view msg, std::string_view where);

      /**
      * Create a Invalid_Argument exception
      * @param msg a description of the problem
      * @param e the exception which caused this one
      */
      Invalid_Argument(std::string_view msg, const std::exception& e);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InvalidArgument; }
};

/**
* An invalid/unknown field name was passed to Public_Key::get_int_field
*/
class BOTAN_PUBLIC_API(3, 0) Unknown_PK_Field_Name final : public Invalid_Argument {
   public:
      /**
      * Create a Unknown_PK_Field_Name exception
      * @param algo_name the name of the key algorithm
      * @param field_name the unknown field which was requested
      */
      Unknown_PK_Field_Name(std::string_view algo_name, std::string_view field_name);
};

/**
* An invalid key length was used
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_Key_Length final : public Invalid_Argument {
   public:
      /**
      * Create a Invalid_Key_Length exception
      * @param name the name of the algorithm which rejected the key
      * @param length the invalid key length in bytes
      */
      Invalid_Key_Length(std::string_view name, size_t length);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InvalidKeyLength; }
};

/**
* An invalid nonce length was used
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_IV_Length final : public Invalid_Argument {
   public:
      /**
      * Create a Invalid_IV_Length exception
      * @param mode the name of the mode which rejected the nonce
      * @param bad_len the invalid nonce length in bytes
      */
      Invalid_IV_Length(std::string_view mode, size_t bad_len);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InvalidNonceLength; }
};

/**
* Invalid_Algorithm_Name Exception
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_Algorithm_Name final : public Invalid_Argument {
   public:
      /**
      * Create a Invalid_Algorithm_Name exception
      * @param name the algorithm name which could not be parsed
      */
      explicit Invalid_Algorithm_Name(std::string_view name);
};

/**
* Encoding_Error Exception
*/
class BOTAN_PUBLIC_API(2, 0) Encoding_Error final : public Exception {
   public:
      /**
      * Create a Encoding_Error exception
      * @param name a description of the encoding which failed
      */
      explicit Encoding_Error(std::string_view name);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::EncodingFailure; }
};

/**
* A decoding error occurred.
*/
class BOTAN_PUBLIC_API(2, 0) Decoding_Error : public Exception {
   public:
      /**
      * Create a Decoding_Error exception
      * @param name a description of the decoding which failed
      */
      explicit Decoding_Error(std::string_view name);

      /**
      * Create a Decoding_Error exception
      * @param category the kind of object being decoded
      * @param err a description of the problem
      */
      Decoding_Error(std::string_view category, std::string_view err);

      /**
      * Create a Decoding_Error exception
      * @param msg a description of the problem
      * @param e the exception which caused this one
      */
      Decoding_Error(std::string_view msg, const std::exception& e);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::DecodingFailure; }
};

/**
* Invalid state was encountered. A request was made on an object while the
* object was in a state where the operation cannot be performed.
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_State : public Exception {
   public:
      /**
      * Create a Invalid_State exception
      * @param err a description of the invalid state
      */
      explicit Invalid_State(std::string_view err) : Exception(err) {}

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InvalidObjectState; }
};

/**
* A PRNG was called on to produce output while still unseeded
*/
class BOTAN_PUBLIC_API(2, 0) PRNG_Unseeded final : public Invalid_State {
   public:
      /**
      * Create a PRNG_Unseeded exception
      * @param algo the name of the unseeded PRNG
      */
      explicit PRNG_Unseeded(std::string_view algo);
};

/**
* The key was not set on an object. This occurs with symmetric objects where
* an operation which requires the key is called prior to set_key being called.
*/
class BOTAN_PUBLIC_API(2, 4) Key_Not_Set : public Invalid_State {
   public:
      /**
      * Create a Key_Not_Set exception
      * @param algo the name of the algorithm whose key was not set
      */
      explicit Key_Not_Set(std::string_view algo);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::KeyNotSet; }
};

/**
* A request was made for some kind of object which could not be located
*/
class BOTAN_PUBLIC_API(2, 0) Lookup_Error : public Exception {
   public:
      /**
      * Create a Lookup_Error exception
      * @param err a description of the object which was not found
      */
      explicit Lookup_Error(std::string_view err) : Exception(err) {}

      /**
      * Create a Lookup_Error exception
      * @param type the kind of object which was requested
      * @param algo the algorithm name which was requested
      * @param provider the provider which was requested, if any
      */
      Lookup_Error(std::string_view type, std::string_view algo, std::string_view provider = "");

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::LookupError; }
};

/**
* Algorithm_Not_Found Exception
*
* @warning This exception type will be removed in the future. Instead
* just catch Lookup_Error.
*/
class BOTAN_PUBLIC_API(2, 0) Algorithm_Not_Found final : public Lookup_Error {
   public:
      /**
      * Create a Algorithm_Not_Found exception
      * @param name the algorithm which was not found
      */
      explicit Algorithm_Not_Found(std::string_view name);
};

/**
* Provider_Not_Found is thrown when a specific provider was requested
* but that provider is not available.
*
* @warning This exception type will be removed in the future. Instead
* just catch Lookup_Error.
*/
class BOTAN_PUBLIC_API(2, 0) Provider_Not_Found final : public Lookup_Error {
   public:
      /**
      * Create a Provider_Not_Found exception
      * @param algo the algorithm which was requested
      * @param provider the provider which was not available
      */
      Provider_Not_Found(std::string_view algo, std::string_view provider);
};

/**
* An AEAD or MAC check detected a message modification
*
* In versions before 2.10, Invalid_Authentication_Tag was named
* Integrity_Failure, it was renamed to make its usage more clear.
*/
class BOTAN_PUBLIC_API(2, 0) Invalid_Authentication_Tag final : public Exception {
   public:
      /**
      * Create a Invalid_Authentication_Tag exception
      * @param msg a description of the failure
      */
      explicit Invalid_Authentication_Tag(std::string_view msg);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InvalidTag; }
};

/**
* For compatibility with older versions
*/
typedef Invalid_Authentication_Tag Integrity_Failure;

/**
* An error occurred while operating on an IO stream
*/
class BOTAN_PUBLIC_API(2, 0) Stream_IO_Error final : public Exception {
   public:
      /**
      * Create a Stream_IO_Error exception
      * @param err a description of the IO failure
      */
      explicit Stream_IO_Error(std::string_view err);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::IoError; }
};

/**
* System_Error
*
* This exception is thrown in the event of an error related to interacting
* with the operating system.
*
* This exception type also (optionally) captures an integer error code eg
* POSIX errno or Windows GetLastError.
*/
class BOTAN_PUBLIC_API(2, 9) System_Error : public Exception {
   public:
      /**
      * Create a System_Error exception
      * @param msg a description of the problem
      */
      explicit System_Error(std::string_view msg) : Exception(msg), m_error_code(0) {}

      /**
      * Create a System_Error exception
      * @param msg a description of the problem
      * @param err_code the operating system error code
      */
      System_Error(std::string_view msg, int err_code);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::SystemError; }

      /**
      * Return the operating system error code associated with this exception
      * @return the operating system error code captured at construction
      */
      int error_code() const noexcept override { return m_error_code; }

   private:
      int m_error_code;
};

/**
* An internal error occurred. If observed, please file a bug.
*/
class BOTAN_PUBLIC_API(2, 0) Internal_Error : public Exception {
   public:
      /**
      * Create a Internal_Error exception
      * @param err a description of the internal error
      */
      explicit Internal_Error(std::string_view err);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::InternalError; }
};

/**
* Not Implemented Exception
*
* This is thrown in the situation where a requested operation is
* logically valid but is not implemented by this version of the library.
*/
class BOTAN_PUBLIC_API(2, 0) Not_Implemented final : public Exception {
   public:
      /**
      * Create a Not_Implemented exception
      * @param err a description of the unimplemented operation
      */
      explicit Not_Implemented(std::string_view err);

      /**
      * Return the error type of this exception
      * @return the error type of this exception
      */
      ErrorType error_type() const noexcept override { return ErrorType::NotImplemented; }
};

/**
* Throw an exception of type E, prefixing the message with the source location
*
* @param file the source file name
* @param line the source line number
* @param func the enclosing function name
* @param args the remaining arguments forwarded to E's constructor
*/
template <typename E, typename... Args>
inline void do_throw_error(const char* file, int line, const char* func, Args... args) {
   throw E(file, line, func, args...);
}

}  // namespace Botan

#if !defined(BOTAN_IS_BEING_BUILT)
   #include <chrono>
#endif

namespace Botan {

/**
* Base class for password based key derivation functions.
*
* Converts a password into a key using a salt and iterated hashing to
* make brute force attacks harder.
*/
class BOTAN_PUBLIC_API(2, 8) PasswordHash /* NOLINT(*-special-member-functions) */ {
   public:
      virtual ~PasswordHash() = default;

      /**
      * Return a free-form string identifying the algorithm and parameters
      */
      virtual std::string to_string() const = 0;

      /**
      * Most password hashes have some notion of iterations.
      */
      virtual size_t iterations() const = 0;

      /**
      * Some password hashing algorithms have a parameter which controls how
      * much memory is used. If not supported by some algorithm, returns 0.
      */
      virtual size_t memory_param() const { return 0; }

      /**
      * Some password hashing algorithms have a parallelism parameter.
      * If the algorithm does not support this notion, then the
      * function returns zero. This allows distinguishing between a
      * password hash which just does not support parallel operation,
      * vs one that does support parallel operation but which has been
      * configured to use a single lane.
      */
      virtual size_t parallelism() const { return 0; }

      /**
      * Returns an estimate of the total number of bytes required to perform this
      * key derivation.
      *
      * If this algorithm uses a small and constant amount of memory, with no
      * effort made towards being memory hard, this function returns 0.
      */
      virtual size_t total_memory_usage() const { return 0; }

      /**
      * Query if this password hash supports a symmetric key
      *
      * @returns true if this password hash supports supplying a key
      */
      virtual bool supports_keyed_operation() const { return false; }

      /**
      * Query if this password hash supports associated data
      *
      * @returns true if this password hash supports supplying associated data
      */
      virtual bool supports_associated_data() const { return false; }

      /**
      * Hash a password into a bitstring
      *
      * Derive a key from the specified @p password and  @p salt, placing it into
      * @p out.
      *
      * @param out a span where the derived key will be placed
      * @param password the password to derive the key from
      * @param salt a randomly chosen salt
      *
      * This function is const, but is not thread safe. Different threads should
      * either use unique objects, or serialize all access.
      */
      void hash(std::span<uint8_t> out, std::string_view password, std::span<const uint8_t> salt) const {
         this->derive_key(out.data(), out.size(), password.data(), password.size(), salt.data(), salt.size());
      }

      /**
      * Hash a password into a bitstring
      *
      * Derive a key from the specified @p password, @p salt, @p
      * associated_data, and secret @p key, placing it into @p out. The
      * @p associated_data and @p key are both allowed to be empty. Currently
      * non-empty AD/key is only supported with Argon2.
      *
      * @param out a span where the derived key will be placed
      * @param password the password to derive the key from
      * @param salt a randomly chosen salt
      * @param associated_data some additional data
      * @param key a secret key
      *
      * This function is const, but is not thread safe. Different threads should
      * either use unique objects, or serialize all access.
      */
      void hash(std::span<uint8_t> out,
                std::string_view password,
                std::span<const uint8_t> salt,
                std::span<const uint8_t> associated_data,
                std::span<const uint8_t> key) const {
         this->derive_key(out.data(),
                          out.size(),
                          password.data(),
                          password.size(),
                          salt.data(),
                          salt.size(),
                          associated_data.data(),
                          associated_data.size(),
                          key.data(),
                          key.size());
      }

      /**
      * Derive a key from a password
      *
      * @param out buffer to store the derived key, must be of out_len bytes
      * @param out_len the desired length of the key to produce
      * @param password the password to derive the key from
      * @param password_len the length of password in bytes
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      *
      * This function is const, but is not thread safe. Different threads should
      * either use unique objects, or serialize all access.
      */
      virtual void derive_key(uint8_t out[],
                              size_t out_len,
                              const char* password,
                              size_t password_len,
                              const uint8_t salt[],
                              size_t salt_len) const = 0;

      /**
      * Derive a key from a password plus additional data and/or a secret key
      *
      * Currently this is only supported for Argon2. Using a non-empty AD or key
      * with other algorithms will cause a Not_Implemented exception.
      *
      * @param out buffer to store the derived key, must be of out_len bytes
      * @param out_len the desired length of the key to produce
      * @param password the password to derive the key from
      * @param password_len the length of password in bytes
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param ad some additional data
      * @param ad_len length of ad in bytes
      * @param key a secret key
      * @param key_len length of key in bytes
      *
      * This function is const, but is not thread safe. Different threads should
      * either use unique objects, or serialize all access.
      */
      virtual void derive_key(uint8_t out[],
                              size_t out_len,
                              const char* password,
                              size_t password_len,
                              const uint8_t salt[],
                              size_t salt_len,
                              const uint8_t ad[],
                              size_t ad_len,
                              const uint8_t key[],
                              size_t key_len) const;
};

/**
* A factory for PasswordHash parameter sets of a particular algorithm
*/
class BOTAN_PUBLIC_API(2, 8) PasswordHashFamily /* NOLINT(*-special-member-functions) */ {
   public:
      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to choose
      * @return a null pointer if the algo/provider combination cannot be found
      */
      static std::unique_ptr<PasswordHashFamily> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name, or throw if the
      * algo/provider combination cannot be found. If provider is
      * empty then best available is chosen.
      */
      static std::unique_ptr<PasswordHashFamily> create_or_throw(std::string_view algo_spec,
                                                                 std::string_view provider = "");

      /**
      * List the providers available for a given password hash
      * @return list of available providers for this algorithm, empty if not available
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      virtual ~PasswordHashFamily() = default;

      /**
      * Return the name of this password hash family
      * @return name of this PasswordHash
      */
      virtual std::string name() const = 0;

      /**
      * Return a new parameter set tuned for this machine
      *
      * Return a password hash instance tuned to run for approximately @p msec
      * milliseconds when producing an output of length @p output_length.
      * (Accuracy may vary, use the command line utility ``botan pbkdf_tune`` to
      * check.)
      *
      * The parameters will be selected to use at most @p max_memory_usage_mb
      * megabytes of memory, or if left as zero any size is allowed.
      *
      * This function works by running a short tuning loop to estimate the
      * performance of the algorithm, then scaling the parameters appropriately
      * to hit the target size. The length of time the tuning loop runs can be
      * controlled using the @p tuning_msec parameter.
      *
      * @param output_length how long the output length will be
      * @param desired_runtime_msec the desired execution time in milliseconds
      *
      * @param max_memory_usage_mb some password hash functions can use a
      * tunable amount of memory, in this case max_memory_usage limits the
      * amount of RAM the returned parameters will require, in mebibytes (2**20
      * bytes). It may require some small amount above the request. Set to nullopt
      * to place no limit at all.
      * @param tuning_msec how long to run the tuning loop
      */
      virtual std::unique_ptr<PasswordHash> tune_params(size_t output_length,
                                                        uint64_t desired_runtime_msec,
                                                        std::optional<size_t> max_memory_usage_mb = {},
                                                        uint64_t tuning_msec = 10) const = 0;

#if !defined(BOTAN_IS_BEING_BUILT)
      /**
      * Return a new parameter set tuned for this machine
      *
      * Return a password hash instance tuned to run for approximately @p msec
      * milliseconds when producing an output of length @p output_length.
      * (Accuracy may vary, use the command line utility ``botan pbkdf_tune`` to
      * check.)
      *
      * The parameters will be selected to use at most @p max_memory_usage_mb
      * megabytes of memory, or if left as zero any size is allowed.
      *
      * This function works by running a short tuning loop to estimate the
      * performance of the algorithm, then scaling the parameters appropriately
      * to hit the target size. The length of time the tuning loop runs can be
      * controlled using the @p tuning_msec parameter.
      *
      * @param output_length how long the output length will be
      * @param msec the desired execution time in milliseconds
      *
      * @param max_memory_usage_mb some password hash functions can use a
      * tunable amount of memory, in this case max_memory_usage limits the
      * amount of RAM the returned parameters will require, in mebibytes (2**20
      * bytes). It may require some small amount above the request. Set to zero
      * to place no limit at all.
      * @param tuning_msec how long to run the tuning loop
      *
      * TODO(Botan4) remove this
      */
      BOTAN_DEPRECATED("Use tune_params instead")
      std::unique_ptr<PasswordHash> tune(size_t output_length,
                                         std::chrono::milliseconds msec,
                                         size_t max_memory_usage_mb = 0,
                                         std::chrono::milliseconds tuning_msec = std::chrono::milliseconds(10)) const {
         std::optional<size_t> max_memory_opt;
         if(max_memory_usage_mb > 0) {
            max_memory_opt = max_memory_usage_mb;
         }

         return this->tune_params(output_length,
                                  static_cast<uint64_t>(msec.count()),
                                  max_memory_opt,
                                  static_cast<uint64_t>(tuning_msec.count()));
      }
#endif
      /**
      * Return some default parameter set for this PBKDF that should be good
      * enough for most users. The value returned may change over time as
      * processing power and attacks improve.
      */
      virtual std::unique_ptr<PasswordHash> default_params() const = 0;

      /**
      * Return a parameter chosen based on a rough approximation with the
      * specified iteration count. The exact value this returns for a particular
      * algorithm may change from over time. Think of it as an alternative to
      * tune, where time is expressed in terms of PBKDF2 iterations rather than
      * milliseconds.
      */
      virtual std::unique_ptr<PasswordHash> from_iterations(size_t iterations) const = 0;

      /**
      * Create a password hash using some scheme specific format. Parameters are as follows:
      * - For PBKDF2, PGP-S2K, and Bcrypt-PBKDF, i1 is iterations
      * - Scrypt uses N, r, p for i{1-3}
      * - Argon2 family uses memory (in KB), iterations, and parallelism for i{1-3}
      * - PKCS12-KDF uses iterations for i1 (the hash and id are fixed by the family name,
      *   e.g. "PKCS12-KDF(SHA-256,1)")
      *
      * All unneeded parameters should be set to 0 or left blank.
      */
      virtual std::unique_ptr<PasswordHash> from_params(size_t i1, size_t i2 = 0, size_t i3 = 0) const = 0;
};

}  // namespace Botan

#if defined(BOTAN_HAS_ARGON2_FMT)

namespace Botan {

class RandomNumberGenerator;

/**
* Generate an Argon2 hash of the specified @p password. The @p y parameter
* specifies the variant: 0 for Argon2d, 1 for Argon2i, and 2 for Argon2id.
*/
std::string BOTAN_PUBLIC_API(2, 11) argon2_generate_pwhash(const char* password,
                                                           size_t password_len,
                                                           RandomNumberGenerator& rng,
                                                           size_t p,
                                                           size_t M,
                                                           size_t t,
                                                           uint8_t y = 2,
                                                           size_t salt_len = 16,
                                                           size_t output_len = 32);

/**
* Check a previously created password hash
*
* Verify an Argon2 password @p hash against the provided @p password. Returns
* false if the input hash seems malformed or if the computed hash does not
* match.
*
* @param password the password to check against
* @param password_len the length of password
* @param hash the stored hash to check against
*/
bool BOTAN_PUBLIC_API(2, 11) argon2_check_pwhash(const char* password, size_t password_len, std::string_view hash);

}  // namespace Botan
#endif

BOTAN_FUTURE_INTERNAL_HEADER(argon2.h)

namespace Botan {

/**
* Argon2 key derivation function
*/
class BOTAN_PUBLIC_API(2, 11) Argon2 final : public PasswordHash {
   public:
      Argon2(uint8_t family, size_t M, size_t t, size_t p);

      /**
      * Derive a new key under the current Argon2 parameter set
      */
      void derive_key(uint8_t out[],
                      size_t out_len,
                      const char* password,
                      size_t password_len,
                      const uint8_t salt[],
                      size_t salt_len) const override;

      void derive_key(uint8_t out[],
                      size_t out_len,
                      const char* password,
                      size_t password_len,
                      const uint8_t salt[],
                      size_t salt_len,
                      const uint8_t ad[],
                      size_t ad_len,
                      const uint8_t key[],
                      size_t key_len) const override;

      std::string to_string() const override;

      size_t M() const { return m_M; }

      size_t t() const { return m_t; }

      size_t p() const { return m_p; }

      bool supports_keyed_operation() const override { return true; }

      bool supports_associated_data() const override { return true; }

      size_t iterations() const override { return t(); }

      size_t parallelism() const override { return p(); }

      size_t memory_param() const override { return M(); }

      size_t total_memory_usage() const override { return M() * 1024; }

      /**
      * Argon2's BLAMKA function
      */
      static void blamka(uint64_t N[128], uint64_t T[128]);

   private:
#if defined(BOTAN_HAS_ARGON2_AVX512)
      static void blamka_avx512(uint64_t N[128], uint64_t T[128]);
#endif

#if defined(BOTAN_HAS_ARGON2_AVX2)
      static void blamka_avx2(uint64_t N[128], uint64_t T[128]);
#endif

#if defined(BOTAN_HAS_ARGON2_SIMD64)
      static void blamka_simd64(uint64_t N[128], uint64_t T[128]);
#endif

      void argon2(uint8_t output[],
                  size_t output_len,
                  const char* password,
                  size_t password_len,
                  const uint8_t salt[],
                  size_t salt_len,
                  const uint8_t key[],
                  size_t key_len,
                  const uint8_t ad[],
                  size_t ad_len) const;

      uint8_t m_family;
      size_t m_M, m_t, m_p;
};

class BOTAN_PUBLIC_API(2, 11) Argon2_Family final : public PasswordHashFamily {
   public:
      BOTAN_FUTURE_EXPLICIT Argon2_Family(uint8_t family);

      std::string name() const override;

      std::unique_ptr<PasswordHash> tune_params(size_t output_len,
                                                uint64_t desired_runtime_msec,
                                                std::optional<size_t> max_memory,
                                                uint64_t tune_msec) const override;

      std::unique_ptr<PasswordHash> default_params() const override;

      std::unique_ptr<PasswordHash> from_iterations(size_t iter) const override;

      std::unique_ptr<PasswordHash> from_params(size_t M, size_t t, size_t p) const override;

   private:
      const uint8_t m_family;
};

/**
* Argon2 key derivation function
*
* @param output the output will be placed here
* @param output_len length of output
* @param password the user password
* @param password_len the length of password
* @param salt the salt
* @param salt_len length of salt
* @param key an optional secret key
* @param key_len the length of key
* @param ad an optional additional input
* @param ad_len the length of ad
* @param y the Argon2 variant (0 = Argon2d, 1 = Argon2i, 2 = Argon2id)
* @param p the parallelization parameter
* @param M the amount of memory to use in Kb
* @param t the number of iterations to use
*/
BOTAN_DEPRECATED("Use PasswordHashFamily+PasswordHash")

inline void argon2(uint8_t output[],
                   size_t output_len,
                   const char* password,
                   size_t password_len,
                   const uint8_t salt[],
                   size_t salt_len,
                   const uint8_t key[],
                   size_t key_len,
                   const uint8_t ad[],
                   size_t ad_len,
                   uint8_t y,
                   size_t p,
                   size_t M,
                   size_t t) {
   auto pwdhash_fam = PasswordHashFamily::create_or_throw([y] {
      switch(y) {
         case 0:
            return "Argon2d";
         case 1:
            return "Argon2i";
         case 2:
            return "Argon2id";
         default:
            throw Not_Implemented("Unknown Argon2 family type");
      }
   }());
   auto pwdhash = pwdhash_fam->from_params(M, t, p);
   pwdhash->derive_key(output, output_len, password, password_len, salt, salt_len, ad, ad_len, key, key_len);
}

}  // namespace Botan

BOTAN_FUTURE_INTERNAL_HEADER(assert.h)

namespace Botan {

// NOLINTBEGIN(*-macro-usage)

/**
* Called when an assertion fails
* Throws an Exception object
*/
[[noreturn]] void BOTAN_PUBLIC_API(2, 0)
   assertion_failure(const char* expr_str, const char* assertion_made, const char* func, const char* file, int line);

/**
* Called when an invalid argument is used
* Throws Invalid_Argument
*/
[[noreturn]] void BOTAN_UNSTABLE_API throw_invalid_argument(const char* message, const char* func, const char* file);

#define BOTAN_ARG_CHECK(expr, msg)                               \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                        \
   do {                                                          \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */              \
      if(!(expr)) {                                              \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */     \
         Botan::throw_invalid_argument(msg, __func__, __FILE__); \
      }                                                          \
   } while(0)

/**
* Called when an invalid state is encountered
* Throws Invalid_State
*/
[[noreturn]] void BOTAN_UNSTABLE_API throw_invalid_state(const char* message, const char* func, const char* file);

#define BOTAN_STATE_CHECK(expr)                                 \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                       \
   do {                                                         \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */             \
      if(!(expr)) {                                             \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */    \
         Botan::throw_invalid_state(#expr, __func__, __FILE__); \
      }                                                         \
   } while(0)

/**
* Make an assertion
*/
#define BOTAN_ASSERT(expr, assertion_made)                                              \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                                               \
   do {                                                                                 \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */                                     \
      if(!(expr)) {                                                                     \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */                            \
         Botan::assertion_failure(#expr, assertion_made, __func__, __FILE__, __LINE__); \
      }                                                                                 \
   } while(0)

/**
* Make an assertion
*/
#define BOTAN_ASSERT_NOMSG(expr)                                            \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                                   \
   do {                                                                     \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */                         \
      if(!(expr)) {                                                         \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */                \
         Botan::assertion_failure(#expr, "", __func__, __FILE__, __LINE__); \
      }                                                                     \
   } while(0)

/**
* Assert that value1 == value2
*/
#define BOTAN_ASSERT_EQUAL(expr1, expr2, assertion_made)                                               \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                                                              \
   do {                                                                                                \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */                                                    \
      if((expr1) != (expr2)) {                                                                         \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */                                           \
         Botan::assertion_failure(#expr1 " == " #expr2, assertion_made, __func__, __FILE__, __LINE__); \
      }                                                                                                \
   } while(0)

/**
* Assert that expr1 (if true) implies expr2 is also true
*/
#define BOTAN_ASSERT_IMPLICATION(expr1, expr2, msg)                                              \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                                                        \
   do {                                                                                          \
      /* NOLINTNEXTLINE(*-simplify-boolean-expr) */                                              \
      if((expr1) && !(expr2)) {                                                                  \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */                                     \
         Botan::assertion_failure(#expr1 " implies " #expr2, msg, __func__, __FILE__, __LINE__); \
      }                                                                                          \
   } while(0)

/**
* Assert that a pointer is not null
*/
#define BOTAN_ASSERT_NONNULL(ptr)                                                         \
   /* NOLINTNEXTLINE(*-avoid-do-while) */                                                 \
   do {                                                                                   \
      if((ptr) == nullptr) {                                                              \
         /* NOLINTNEXTLINE(bugprone-lambda-function-name) */                              \
         Botan::assertion_failure(#ptr " is not null", "", __func__, __FILE__, __LINE__); \
      }                                                                                   \
   } while(0)

#if defined(BOTAN_ENABLE_DEBUG_ASSERTS)

   #define BOTAN_DEBUG_ASSERT(expr) BOTAN_ASSERT_NOMSG(expr)

#else

   #define BOTAN_DEBUG_ASSERT(expr)       \
      do { /* NOLINT(*-avoid-do-while) */ \
      } while(0)

#endif

/**
* Mark variable as unused.
*
* Takes any number of arguments and marks all as unused, for instance
* BOTAN_UNUSED(a); or BOTAN_UNUSED(x, y, z);
*/
template <typename... T>
constexpr void ignore_params([[maybe_unused]] const T&... args) {}

#define BOTAN_UNUSED Botan::ignore_params

/**
* Define Botan::assert_unreachable and BOTAN_ASSERT_UNREACHABLE
*
* This is intended to be used in the same situations as `std::unreachable()`;
* a codepath that (should not) be reachable but where the compiler cannot
* tell that it is unreachable.
*
* Unlike `std::unreachable()`, or equivalent compiler builtins like GCC's
* `__builtin_unreachable`, this function is not UB. By default it will
* throw an exception. If `BOTAN_TERMINATE_ON_ASSERTS` is defined, it will
* instead print a message to stderr and abort.
*
* Due to this difference, and the fact that it is not inlined, calling
* this is significantly more costly than using `std::unreachable`.
*
* @param file the source file the call occurred in
* @param line the source line the call occurred on
*/
[[noreturn]] void BOTAN_UNSTABLE_API assert_unreachable(const char* file, int line);

#define BOTAN_ASSERT_UNREACHABLE() Botan::assert_unreachable(__FILE__, __LINE__)

// NOLINTEND(*-macro-usage)

}  // namespace Botan


/*
* We only include <chrono> in downstream applications to avoid
* breaking semver wrt RandomNumberGenerator::reseed. Within the
* library we avoid it because it slows down compilation significantly.
*
* TODO(Botan4): remove this entirely
*/
#if !defined(BOTAN_IS_BEING_BUILT)
   #include <chrono>
#endif

namespace Botan {

class Entropy_Sources;

/**
* An interface to a cryptographic random number generator
*/
class BOTAN_PUBLIC_API(2, 0) RandomNumberGenerator {
   public:
      /**
      * Userspace RNGs like HMAC_DRBG will reseed after a specified number
      * of outputs are generated. Set to zero to disable automatic reseeding.
      */
      static constexpr size_t DefaultReseedInterval = 1024;

      /**
      * Number of entropy bits polled for reseeding userspace RNGs like HMAC_DRBG
      */
      static constexpr size_t DefaultPollBits = 256;

      virtual ~RandomNumberGenerator() = default;

      /**
      * Default constructor
      */
      RandomNumberGenerator() = default;

      /*
      * Never copy a RNG, create a new one
      */
      RandomNumberGenerator(const RandomNumberGenerator& rng) = delete;
      RandomNumberGenerator& operator=(const RandomNumberGenerator& rng) = delete;

      /**
      * Move constructor
      */
      RandomNumberGenerator(RandomNumberGenerator&& rng) = default;

      /**
      * Move assignment
      * @return reference to this
      */
      RandomNumberGenerator& operator=(RandomNumberGenerator&& rng) = default;

      /**
      * Randomize a byte array.
      *
      * May block shortly if e.g. the RNG is not yet initialized
      * or a retry because of insufficient entropy is needed.
      *
      * @param output the byte array to hold the random output.
      * @throws PRNG_Unseeded if the RNG fails because it has not enough entropy
      * @throws Exception if the RNG fails
      */
      void randomize(std::span<uint8_t> output) { this->fill_bytes_with_input(output, {}); }

      /**
      * Randomize a byte array
      * @param output the byte array to hold the random output
      * @param length the number of bytes to generate
      */
      void randomize(uint8_t output[], size_t length) { this->randomize(std::span(output, length)); }

      /**
      * Returns false if it is known that this RNG object is not able to accept
      * externally provided inputs (via add_entropy, randomize_with_input, etc).
      * In this case, any such provided inputs are ignored.
      *
      * If this function returns true, then inputs may or may not be accepted.
      */
      virtual bool accepts_input() const = 0;

      /**
      * Incorporate some additional data into the RNG state. For
      * example adding nonces or timestamps from a peer's protocol
      * message can help hedge against VM state rollback attacks.
      * A few RNG types do not accept any externally provided input,
      * in which case this function is a no-op.
      *
      * @param input a byte array containing the entropy to be added
      * @throws Exception may throw if the RNG accepts input, but adding the entropy failed.
      */
      void add_entropy(std::span<const uint8_t> input) { this->fill_bytes_with_input({}, input); }

      /**
      * Incorporate some additional data into the RNG state
      * @param input a byte array containing the entropy to be added
      * @param length the number of bytes in input
      */
      void add_entropy(const uint8_t input[], size_t length) { this->add_entropy(std::span(input, length)); }

      /**
      * Incorporate some additional data into the RNG state.
      */
      template <typename T>
         requires std::is_standard_layout_v<T> && std::is_trivial_v<T>
      void add_entropy_T(const T& t) {
         this->add_entropy(reinterpret_cast<const uint8_t*>(&t), sizeof(T));
      }

      /**
      * Incorporate entropy into the RNG state then produce output.
      * Some RNG types implement this using a single operation, default
      * calls add_entropy + randomize in sequence.
      *
      * Use this to further bind the outputs to your current
      * process/protocol state. For instance if generating a new key
      * for use in a session, include a session ID or other such
      * value. See NIST SP 800-90 A, B, C series for more ideas.
      *
      * @param output buffer to hold the random output
      * @param input entropy buffer to incorporate
      * @throws PRNG_Unseeded if the RNG fails because it has not enough entropy
      * @throws Exception if the RNG fails
      * @throws Exception may throw if the RNG accepts input, but adding the entropy failed.
      */
      void randomize_with_input(std::span<uint8_t> output, std::span<const uint8_t> input) {
         this->fill_bytes_with_input(output, input);
      }

      /**
      * Randomize a byte array, first incorporating additional input
      * @param output the byte array to hold the random output
      * @param output_len the number of bytes to generate
      * @param input a byte array containing the entropy to be added
      * @param input_len the number of bytes in input
      */
      void randomize_with_input(uint8_t output[], size_t output_len, const uint8_t input[], size_t input_len) {
         this->randomize_with_input(std::span(output, output_len), std::span(input, input_len));
      }

      /**
      * This calls `randomize_with_input` using system specific values
      *
      * This first attempts to provide input to the underlying RNG from some system
      * specific source. If a system RNG is available, it is queried and the output from
      * the system RNG is used as the additional input. Otherwise 12 bytes consisting of
      * the local clock plus the current process ID are used.
      *
      * For a stateful RNG that was already correctly seeded with sufficient
      * cryptographically secure material, using non-random but potentially unique data
      * as the extra input can help protect against problems with fork, VM state
      * rollback, or other cases where somehow an RNG state is duplicated. If both of
      * the duplicated RNG states later incorporate some input, even predictable input,
      * their outputs will diverge.
      *
      * @param output buffer to hold the random output
      * @throws PRNG_Unseeded if the RNG fails because it has not enough entropy
      * @throws Exception if the RNG fails
      * @throws Exception may throw if the RNG accepts input, but adding the entropy failed.
      */
      void randomize_with_ts_input(std::span<uint8_t> output);

      /**
      * Randomize a byte array, using timestamps as additional input
      * @param output the byte array to hold the random output
      * @param output_len the number of bytes to generate
      */
      void randomize_with_ts_input(uint8_t output[], size_t output_len) {
         this->randomize_with_ts_input(std::span(output, output_len));
      }

      /**
      * Return the name of this RNG type
      * @return the name of this RNG type
      */
      virtual std::string name() const = 0;

      /**
      * Clear all internally held values of this RNG
      * @post is_seeded() == false if the RNG has an internal state that can be cleared.
      */
      virtual void clear() = 0;

      /**
      * Check whether this RNG is seeded.
      * @return true if this RNG was already seeded, false otherwise.
      */
      virtual bool is_seeded() const = 0;

      /**
      * Poll provided sources for up to poll_bits bits of entropy.
      * Returns estimate of the number of bits collected.
      * Sets the seeded state to true if enough entropy was added.
      *
      * @throws Exception if RNG accepts input but reseeding failed.
      */
      size_t reseed_from(Entropy_Sources& srcs, size_t poll_bits = RandomNumberGenerator::DefaultPollBits) {
         return reseed_from_sources(srcs, poll_bits);
      }

      /**
      * Reseed by reading specified bits from the RNG
      *
      * Sets the seeded state to true if enough entropy was added.
      *
      * @throws Exception if RNG accepts input but reseeding failed.
      */
      void reseed_from(RandomNumberGenerator& rng, size_t poll_bits = RandomNumberGenerator::DefaultPollBits) {
         return reseed_from_rng(rng, poll_bits);
      }

      // Some utility functions built on the interface above:

      /**
      * Fill a given byte container with @p bytes random bytes
      *
      * @todo deprecate this overload (in favor of randomize())
      *
      * @param  v     the container to be filled with @p bytes random bytes
      * @throws Exception if RNG fails
      */
      void random_vec(std::span<uint8_t> v) { this->randomize(v); }

      /**
      * Resize a given byte container to @p bytes and fill it with random bytes
      *
      * @tparam T     the desired byte container type (e.g std::vector<uint8_t>)
      * @param  v     the container to be filled with @p bytes random bytes
      * @param  bytes number of random bytes to initialize the container with
      * @throws Exception if RNG or memory allocation fails
      */
      template <concepts::resizable_byte_buffer T>
      void random_vec(T& v, size_t bytes) {
         v.resize(bytes);
         random_vec(v);
      }

      /**
      * Create some byte container type and fill it with some random @p bytes.
      *
      * @tparam T     the desired byte container type (e.g std::vector<uint8_t>)
      * @param  bytes number of random bytes to initialize the container with
      * @return       a container of type T with @p bytes random bytes
      * @throws Exception if RNG or memory allocation fails
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
         requires std::default_initializable<T>
      T random_vec(size_t bytes) {
         T result;
         random_vec(result, bytes);
         return result;
      }

      /**
       * Create a std::array of @p bytes random bytes
       */
      template <size_t bytes>
      std::array<uint8_t, bytes> random_array() {
         std::array<uint8_t, bytes> result{};
         random_vec(result);
         return result;
      }

      /**
      * Return a random byte
      * @return random byte
      * @throws PRNG_Unseeded if the RNG fails because it has not enough entropy
      * @throws Exception if the RNG fails
      */
      uint8_t next_byte() {
         uint8_t b = 0;
         this->fill_bytes_with_input(std::span(&b, 1), {});
         return b;
      }

      /**
      * Generate a single random byte which is not zero
      * @return a random byte that is greater than zero
      * @throws PRNG_Unseeded if the RNG fails because it has not enough entropy
      * @throws Exception if the RNG fails
      */
      uint8_t next_nonzero_byte() {
         uint8_t b = this->next_byte();
         while(b == 0) {
            b = this->next_byte();
         }
         return b;
      }

      /**
      * Reseed by reading specified bits from the RNG
      *
      * Sets the seeded state to true if enough entropy was added.
      *
      * @throws Exception if RNG accepts input but reseeding failed.
      */
      virtual void reseed_from_rng(RandomNumberGenerator& rng,
                                   size_t poll_bits = RandomNumberGenerator::DefaultPollBits);

#if !defined(BOTAN_IS_BEING_BUILT)
      /**
      * Default poll timeout
      */
      static constexpr auto DefaultPollTimeout = std::chrono::milliseconds(50);

      /**
       * Poll provided sources for up to poll_bits bits of entropy.
       * Returns estimate of the number of bits collected.
       *
       * Sets the seeded state to true if enough entropy was added.
       *
       * TODO(Botan4) remove this function
       */
      BOTAN_DEPRECATED("Use reseed_from_sources")
      inline size_t reseed(Entropy_Sources& srcs,
                           size_t poll_bits = RandomNumberGenerator::DefaultPollBits,
                           std::chrono::milliseconds /*unused_timeout*/ = DefaultPollTimeout) {
         return reseed_from(srcs, poll_bits);
      }
#endif

   protected:
      /**
      * Poll provided sources for up to poll_bits bits of entropy.
      * Returns estimate of the number of bits collected.
      * Sets the seeded state to true if enough entropy was added.
      *
      * @throws Exception if RNG accepts input but reseeding failed.
      */
      virtual size_t reseed_from_sources(Entropy_Sources& srcs,
                                         size_t poll_bits = RandomNumberGenerator::DefaultPollBits);

      /**
      * Generic interface to provide entropy to a concrete implementation and to
      * fill a given buffer with random output. Both @p output and @p input may
      * be empty and should be ignored in that case. If both buffers are
      * non-empty implementations should typically first apply the @p input data
      * and then generate random data into @p output.
      *
      * This method must be implemented by all RandomNumberGenerator sub-classes.
      *
      * @param output  Byte buffer to write random bytes into. Implementations
      *                should not read from this buffer.
      * @param input   Byte buffer that may contain bytes to be incorporated in
      *                the RNG's internal state. Implementations may choose to
      *                ignore the bytes in this buffer.
      */
      virtual void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> input) = 0;
};

/**
* Convenience typedef
*/
typedef RandomNumberGenerator RNG;

/**
* Hardware_RNG exists to tag hardware RNG types (PKCS11_RNG, TPM_RNG, Processor_RNG)
*/
class BOTAN_PUBLIC_API(2, 0) Hardware_RNG : public RandomNumberGenerator {
   public:
      /**
      * No-op clear implementation - no way to clear state of a hardware RNG
      */
      void clear() final {}
};

/**
* Null/stub RNG - fails if you try to use it for anything
* This is not generally useful except for in certain tests
*/
class BOTAN_PUBLIC_API(2, 0) Null_RNG final : public RandomNumberGenerator {
   public:
      /**
      * Test whether this RNG has been seeded
      * @return true if this RNG is seeded and ready for use
      */
      bool is_seeded() const override { return false; }

      /**
      * Test whether this RNG accepts externally provided input
      * @return false if this RNG is known to ignore provided inputs
      */
      bool accepts_input() const override { return false; }

      /**
      * Clear all internally held values of this RNG
      */
      void clear() override {}

      /**
      * Return the name of this RNG type
      * @return the name of this RNG type
      */
      std::string name() const override { return "Null_RNG"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override;
};

}  // namespace Botan

namespace Botan {

class Stateful_RNG;

/**
* A userspace PRNG
*/
class BOTAN_PUBLIC_API(2, 0) AutoSeeded_RNG final : public RandomNumberGenerator {
   public:
      /**
      * Test whether this RNG has been seeded
      * @return true if this RNG is seeded and ready for use
      */
      bool is_seeded() const override;

      /**
      * Test whether this RNG accepts externally provided input
      * @return false if this RNG is known to ignore provided inputs
      */
      bool accepts_input() const override { return true; }

      /**
      * Mark state as requiring a reseed on next use
      */
      void force_reseed();

      /**
      * Poll the provided sources for entropy and reseed from them
      * @param srcs the entropy sources to poll
      * @param poll_bits the number of bits to collect
      * @return estimate of the number of bits collected
      */
      size_t reseed_from_sources(Entropy_Sources& srcs,
                                 size_t poll_bits = RandomNumberGenerator::DefaultPollBits) override;

      /**
      * Return the name of this RNG type
      * @return the name of this RNG type
      */
      std::string name() const override;

      /**
      * Clear all internally held values of this RNG
      */
      void clear() override;

      /**
      * Uses the system RNG (if available) or else a default group of
      * entropy sources (all other systems) to gather seed material.
      *
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      BOTAN_FUTURE_EXPLICIT AutoSeeded_RNG(size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval);

      /**
      * Create an AutoSeeded_RNG which will get seed material from some other
      * RNG instance. For example you could provide a reference to the system
      * RNG or a hardware RNG.
      *
      * @param underlying_rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      BOTAN_FUTURE_EXPLICIT AutoSeeded_RNG(RandomNumberGenerator& underlying_rng,
                                           size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval);

      /**
      * Create an AutoSeeded_RNG which will get seed material from a set of
      * entropy sources.
      *
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      BOTAN_FUTURE_EXPLICIT AutoSeeded_RNG(Entropy_Sources& entropy_sources,
                                           size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval);

      /**
      * Create an AutoSeeded_RNG which will get seed material from both an
      * underlying RNG and a set of entropy sources.
      *
      * @param underlying_rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      AutoSeeded_RNG(RandomNumberGenerator& underlying_rng,
                     Entropy_Sources& entropy_sources,
                     size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval);

      AutoSeeded_RNG(const AutoSeeded_RNG& other) = delete;
      /**
      * Move constructor
      */
      AutoSeeded_RNG(AutoSeeded_RNG&& other) noexcept;
      AutoSeeded_RNG& operator=(const AutoSeeded_RNG& other) = delete;
      AutoSeeded_RNG& operator=(AutoSeeded_RNG&& other) = delete;

      ~AutoSeeded_RNG() override;

   private:
      void fill_bytes_with_input(std::span<uint8_t> out, std::span<const uint8_t> in) override;

   private:
      std::unique_ptr<Stateful_RNG> m_rng;
};

}  // namespace Botan

namespace Botan {

/**
* Perform base32 encoding
* @param output an array of at least base32_encode_max_output bytes
* @param input is some binary data
* @param input_length length of input in bytes
* @param input_consumed is an output parameter which says how many
*        bytes of input were actually consumed. If less than
*        input_length, then the range input[consumed:length]
*        should be passed in later along with more input.
* @param final_inputs true iff this is the last input, in which case
         padding chars will be applied if needed
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 7)
   base32_encode(char output[], const uint8_t input[], size_t input_length, size_t& input_consumed, bool final_inputs);

/**
* Perform base32 encoding
* @param input some input
* @param input_length length of input in bytes
* @return base32 representation of input
*/
std::string BOTAN_PUBLIC_API(2, 7) base32_encode(const uint8_t input[], size_t input_length);

/**
* Perform base32 encoding
* @param input some input
* @return base32 representation of input
*/
inline std::string base32_encode(std::span<const uint8_t> input) {
   return base32_encode(input.data(), input.size());
}

/**
* Perform base32 decoding
* @param output an array of at least base32_decode_max_output bytes
* @param input some base32 input
* @param input_length length of input in bytes
* @param input_consumed is an output parameter which says how many
*        bytes of input were actually consumed. If less than
*        input_length, then the range input[consumed:length]
*        should be passed in later along with more input.
* @param final_inputs true iff this is the last input, in which case
         padding is allowed
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 7) base32_decode(uint8_t output[],
                                            const char input[],
                                            size_t input_length,
                                            size_t& input_consumed,
                                            bool final_inputs,
                                            bool ignore_ws = true);

/**
* Perform base32 decoding
* @param output an array of at least base32_decode_max_output bytes
* @param input some base32 input
* @param input_length length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 7)
   base32_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform base32 decoding
* @param output an array of at least base32_decode_max_output bytes
* @param input some base32 input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 7) base32_decode(uint8_t output[], std::string_view input, bool ignore_ws = true);

/**
* Perform base32 decoding
* @param input some base32 input
* @param input_length the length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded base32 output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 7)
   base32_decode(const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform base32 decoding
* @param input some base32 input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded base32 output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 7) base32_decode(std::string_view input, bool ignore_ws = true);

/**
* Calculate the size of output buffer for base32_encode
* @param input_length the length of input in bytes
* @return the size of output buffer in bytes
*/
size_t BOTAN_PUBLIC_API(3, 8) base32_encode_max_output(size_t input_length);

/**
* Calculate the size of output buffer for base32_decode
* @param input_length the length of input in bytes
* @return the size of output buffer in bytes
*/
size_t BOTAN_PUBLIC_API(3, 8) base32_decode_max_output(size_t input_length);

}  // namespace Botan

namespace Botan {

/**
* Perform base64 encoding
* @param output an array of at least base64_encode_max_output bytes
* @param input is some binary data
* @param input_length length of input in bytes
* @param input_consumed is an output parameter which says how many
*        bytes of input were actually consumed. If less than
*        input_length, then the range input[consumed:length]
*        should be passed in later along with more input.
* @param final_inputs true iff this is the last input, in which case
         padding chars will be applied if needed
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 0)
   base64_encode(char output[], const uint8_t input[], size_t input_length, size_t& input_consumed, bool final_inputs);

/**
* Perform base64 encoding
* @param input some input
* @param input_length length of input in bytes
* @return base64adecimal representation of input
*/
std::string BOTAN_PUBLIC_API(2, 0) base64_encode(const uint8_t input[], size_t input_length);

/**
* Perform base64 encoding
* @param input some input
* @return base64adecimal representation of input
*/
inline std::string base64_encode(std::span<const uint8_t> input) {
   return base64_encode(input.data(), input.size());
}

/**
* Perform base64 decoding
* @param output an array of at least base64_decode_max_output bytes
* @param input some base64 input
* @param input_length length of input in bytes
* @param input_consumed is an output parameter which says how many
*        bytes of input were actually consumed. If less than
*        input_length, then the range input[consumed:length]
*        should be passed in later along with more input.
* @param final_inputs true iff this is the last input, in which case
         padding is allowed
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 0) base64_decode(uint8_t output[],
                                            const char input[],
                                            size_t input_length,
                                            size_t& input_consumed,
                                            bool final_inputs,
                                            bool ignore_ws = true);

/**
* Perform base64 decoding
* @param output an array of at least base64_decode_max_output bytes
* @param input some base64 input
* @param input_length length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 0)
   base64_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform base64 decoding
* @param output an array of at least base64_decode_max_output bytes
* @param input some base64 input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(3, 0) base64_decode(uint8_t output[], std::string_view input, bool ignore_ws = true);

/**
* Perform base64 decoding
* @param output a contiguous byte buffer of at least base64_decode_max_output bytes
* @param input some base64 input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(3, 0) base64_decode(std::span<uint8_t> output, std::string_view input, bool ignore_ws = true);

/**
* Perform base64 decoding
* @param input some base64 input
* @param input_length the length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded base64 output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 0)
   base64_decode(const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform base64 decoding
* @param input some base64 input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded base64 output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(3, 0) base64_decode(std::string_view input, bool ignore_ws = true);

/**
* Calculate the size of output buffer for base64_encode
* @param input_length the length of input in bytes
* @return the size of output buffer in bytes
*/
size_t BOTAN_PUBLIC_API(2, 1) base64_encode_max_output(size_t input_length);

/**
* Calculate the size of output buffer for base64_decode
* @param input_length the length of input in bytes
* @return the size of output buffer in bytes
*/
size_t BOTAN_PUBLIC_API(2, 1) base64_decode_max_output(size_t input_length);

}  // namespace Botan

namespace Botan {

/**
* This class represents a block cipher object.
*/
class BOTAN_PUBLIC_API(2, 0) BlockCipher : public SymmetricAlgorithm {
   public:
      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to choose
      * @return a null pointer if the algo/provider combination cannot be found
      */
      static std::unique_ptr<BlockCipher> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name, or throw if the
      * algo/provider combination cannot be found. If provider is
      * empty then best available is chosen.
      */
      static std::unique_ptr<BlockCipher> create_or_throw(std::string_view algo_spec, std::string_view provider = "");

      /**
      * List the providers available for a given block cipher
      * @return list of available providers for this algorithm, empty if not available
      * @param algo_spec algorithm name
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Multiplier on a block cipher's native parallelism
      *
      * Usually notable performance gains come from further loop blocking,
      * at least for 2 or 4x
      */
      static constexpr size_t ParallelismMult = 4;

      /**
      * Return the block size of this cipher
      * @return block size of this algorithm
      */
      virtual size_t block_size() const = 0;

      /**
      * Return how many blocks this cipher processes in parallel
      * @return native parallelism of this cipher in blocks
      */
      virtual size_t parallelism() const { return 1; }

      /**
      * Return the preferred input size for bulk processing
      * @return preferred parallelism of this cipher in bytes
      */
      size_t parallel_bytes() const { return parallelism() * block_size() * BlockCipher::ParallelismMult; }

      /**
      * Return the name of the provider implementing this object
      * @return provider information about this implementation. Default is "base",
      * might also return "sse2", "avx2", "openssl", or some other arbitrary string.
      */
      virtual std::string provider() const { return "base"; }

      /**
      * Encrypt a block.
      * @param in The plaintext block to be encrypted as a byte array.
      * Must be of length block_size().
      * @param out The byte array designated to hold the encrypted block.
      * Must be of length block_size().
      */
      void encrypt(const uint8_t in[], uint8_t out[]) const { encrypt_n(in, out, 1); }

      /**
      * Decrypt a block.
      * @param in The ciphertext block to be decrypted as a byte array.
      * Must be of length block_size().
      * @param out The byte array designated to hold the decrypted block.
      * Must be of length block_size().
      */
      void decrypt(const uint8_t in[], uint8_t out[]) const { decrypt_n(in, out, 1); }

      /**
      * Encrypt a block.
      * @param block the plaintext block to be encrypted
      * Must be of length block_size(). Will hold the result when the function
      * has finished.
      */
      void encrypt(uint8_t block[]) const { encrypt_n(block, block, 1); }

      /**
      * Decrypt a block.
      * @param block the ciphertext block to be decrypted
      * Must be of length block_size(). Will hold the result when the function
      * has finished.
      */
      void decrypt(uint8_t block[]) const { decrypt_n(block, block, 1); }

      /**
      * Encrypt one or more blocks
      * @param block the input/output buffer (multiple of block_size())
      */
      void encrypt(std::span<uint8_t> block) const {
         return encrypt_n(block.data(), block.data(), block.size() / block_size());
      }

      /**
      * Decrypt one or more blocks
      * @param block the input/output buffer (multiple of block_size())
      */
      void decrypt(std::span<uint8_t> block) const {
         return decrypt_n(block.data(), block.data(), block.size() / block_size());
      }

      /**
      * Encrypt one or more blocks
      * @param in the input buffer (multiple of block_size())
      * @param out the output buffer (same size as in)
      */
      void encrypt(std::span<const uint8_t> in, std::span<uint8_t> out) const {
         return encrypt_n(in.data(), out.data(), in.size() / block_size());
      }

      /**
      * Decrypt one or more blocks
      * @param in the input buffer (multiple of block_size())
      * @param out the output buffer (same size as in)
      */
      void decrypt(std::span<const uint8_t> in, std::span<uint8_t> out) const {
         return decrypt_n(in.data(), out.data(), in.size() / block_size());
      }

      /**
      * Encrypt one or more blocks
      * @param in the input buffer (multiple of block_size())
      * @param out the output buffer (same size as in)
      * @param blocks the number of blocks to process
      */
      virtual void encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const = 0;

      /**
      * Decrypt one or more blocks
      * @param in the input buffer (multiple of block_size())
      * @param out the output buffer (same size as in)
      * @param blocks the number of blocks to process
      */
      virtual void decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const = 0;

      /**
      * Encrypt blocks in XEX mode: XOR with the mask, encrypt, then XOR again
      * @param data the input/output buffer of blocks*block_size() bytes
      * @param mask the mask to XOR with, same size as data
      * @param blocks the number of blocks to process
      */
      BOTAN_DEPRECATED("Deprecated no replacement")
      void encrypt_n_xex(uint8_t data[], const uint8_t mask[], size_t blocks) const {
         const size_t BS = block_size();
         for(size_t i = 0; i != blocks * BS; ++i) {
            data[i] ^= mask[i];
         }
         encrypt_n(data, data, blocks);
         for(size_t i = 0; i != blocks * BS; ++i) {
            data[i] ^= mask[i];
         }
      }

      /**
      * Decrypt blocks in XEX mode: XOR with the mask, decrypt, then XOR again
      * @param data the input/output buffer of blocks*block_size() bytes
      * @param mask the mask to XOR with, same size as data
      * @param blocks the number of blocks to process
      */
      BOTAN_DEPRECATED("Deprecated no replacement")
      void decrypt_n_xex(uint8_t data[], const uint8_t mask[], size_t blocks) const {
         const size_t BS = block_size();
         for(size_t i = 0; i != blocks * BS; ++i) {
            data[i] ^= mask[i];
         }
         decrypt_n(data, data, blocks);
         for(size_t i = 0; i != blocks * BS; ++i) {
            data[i] ^= mask[i];
         }
      }

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      virtual std::unique_ptr<BlockCipher> new_object() const = 0;

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      BlockCipher* clone() const { return this->new_object().release(); }
};

/**
* Tweakable block ciphers allow setting a tweak which is a non-keyed
* value which affects the encryption/decryption operation.
*/
class BOTAN_PUBLIC_API(2, 8) Tweakable_Block_Cipher : public BlockCipher {
   public:
      /**
      * Set the tweak value. This must be called after setting a key. The value
      * persists until either set_tweak, set_key, or clear is called.
      * Different algorithms support different tweak length(s). If called with
      * an unsupported length, Invalid_Argument will be thrown.
      */
      virtual void set_tweak(const uint8_t tweak[], size_t len) = 0;
};

/**
* Represents a block cipher with a single fixed block size
*/
template <size_t BS, size_t KMIN, size_t KMAX = 0, size_t KMOD = 1, typename BaseClass = BlockCipher>
class Block_Cipher_Fixed_Params : public BaseClass {
   public:
      enum { BLOCK_SIZE = BS }; /* NOLINT(*-enum-size,*-use-enum-class) */

      /**
      * Return the block size of this cipher
      * @return the fixed block size BS
      */
      size_t block_size() const final { return BS; }

      /**
      * Return the key lengths supported by this cipher
      * @return the fixed key length specification
      */
      Key_Length_Specification key_spec() const final { return Key_Length_Specification(KMIN, KMAX, KMOD); }
};

}  // namespace Botan

namespace Botan {

/**
* This class represents any kind of computation which uses an internal
* state, such as hash functions or MACs
*/
class BOTAN_PUBLIC_API(2, 0) Buffered_Computation /* NOLINT(*special-member-functions) */ {
   public:
      /**
      * Return the output length of this function
      * @return length of the output of this function in bytes
      */
      virtual size_t output_length() const = 0;

      /**
      * Add new input to process.
      * @param in the input to process as a byte array
      * @param length of param in in bytes
      */
      void update(const uint8_t in[], size_t length) { add_data({in, length}); }

      /**
      * Add new input to process.
      * @param in the input to process as a contiguous data range
      */
      void update(std::span<const uint8_t> in) { add_data(in); }

      /**
      * Add new input to process, encoded as a big-endian integer
      * @param val the value to process
      */
      void update_be(uint16_t val);

      /**
      * Add new input to process, encoded as a big-endian integer
      * @param val the value to process
      */
      void update_be(uint32_t val);

      /**
      * Add new input to process, encoded as a big-endian integer
      * @param val the value to process
      */
      void update_be(uint64_t val);

      /**
      * Add new input to process, encoded as a little-endian integer
      * @param val the value to process
      */
      void update_le(uint16_t val);

      /**
      * Add new input to process, encoded as a little-endian integer
      * @param val the value to process
      */
      void update_le(uint32_t val);

      /**
      * Add new input to process, encoded as a little-endian integer
      * @param val the value to process
      */
      void update_le(uint64_t val);

      /**
      * Add new input to process.
      * @param str the input to process as a std::string_view. Will be interpreted
      * as a byte array based on the strings encoding.
      */
      void update(std::string_view str);

      /**
      * Process a single byte.
      * @param in the byte to process
      */
      void update(uint8_t in) { add_data({&in, 1}); }

      /**
      * Complete the computation and retrieve the final result.
      * @param out The byte array to be filled with the result, which
      * must be of length output_length()
      */
      void final(uint8_t out[]) { final_result({out, output_length()}); }

      /**
      * Complete the computation and retrieve the final result as a container.
      * @return a contiguous container holding the result
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T final() {
         T output(output_length());
         final_result(output);
         return output;
      }

      /**
      * Complete the computation and retrieve the final result
      * @return a std::vector holding the result
      */
      std::vector<uint8_t> final_stdvec() { return final<std::vector<uint8_t>>(); }

      /**
      * Complete the computation and retrieve the final result
      * @param out the buffer to write the result to, must be output_length() bytes
      */
      void final(std::span<uint8_t> out);

      /**
      * Complete the computation and retrieve the final result
      * @param out a container which is resized to hold the result
      */
      template <concepts::resizable_byte_buffer T>
      void final(T& out) {
         out.resize(output_length());
         final_result(out);
      }

      /**
      * Update and finalize computation. Does the same as calling update()
      * and final() consecutively.
      * @param in the input to process as a byte array
      * @param length the length of the byte array
      * @result the result of the call to final()
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T process(const uint8_t in[], size_t length) {
         update(in, length);
         return final<T>();
      }

      /**
      * Update and finalize computation. Does the same as calling update()
      * and final() consecutively.
      * @param in the input to process as a string
      * @result the result of the call to final()
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T process(std::string_view in) {
         update(in);
         return final<T>();
      }

      /**
      * Update and finalize computation. Does the same as calling update()
      * and final() consecutively.
      * @param in the input to process as a contiguous container
      * @result the result of the call to final()
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T process(std::span<const uint8_t> in) {
         update(in);
         return final<T>();
      }

      virtual ~Buffered_Computation() = default;

   private:
      /**
      * Add more data to the computation
      * @param input is an input buffer
      */
      virtual void add_data(std::span<const uint8_t> input) = 0;

      /**
      * Write the final output to out
      * @param out is an output buffer of output_length()
      */
      virtual void final_result(std::span<uint8_t> out) = 0;
};

}  // namespace Botan

// NOLINTBEGIN(*-macro-usage)

BOTAN_FUTURE_INTERNAL_HEADER(compiler.h)

/*
* Define BOTAN_COMPILER_HAS_BUILTIN
*/
#if defined(__has_builtin)
   #define BOTAN_COMPILER_HAS_BUILTIN(x) __has_builtin(x)
#else
   #define BOTAN_COMPILER_HAS_BUILTIN(x) 0
#endif

/*
* Define BOTAN_COMPILER_HAS_ATTRIBUTE
*/
#if defined(__has_attribute)
   #define BOTAN_COMPILER_HAS_ATTRIBUTE(x) __has_attribute(x)
   #define BOTAN_COMPILER_ATTRIBUTE(x) __attribute__((x))
#else
   #define BOTAN_COMPILER_HAS_ATTRIBUTE(x) 0
   #define BOTAN_COMPILER_ATTRIBUTE(x) /**/
#endif

/*
* Hack for Loongarch64 GCC bug
*
* For some reason __has_attribute(target) is true, but it does not support the
* target attribute... this supposedly is fixed in GCC 15 but this is untested.
*/
#if defined(__GNUC__) && defined(__loongarch64) && (__GNUC__ <= 14)
   #define BOTAN_COMPILER_DOES_NOT_HAVE_TARGET_ATTRIBUTE
#endif

/*
* Define BOTAN_FUNC_ISA
*
* TODO(Botan4) Move this to isa_extn.h
*/
#if BOTAN_COMPILER_HAS_ATTRIBUTE(target) && !defined(BOTAN_COMPILER_DOES_NOT_HAVE_TARGET_ATTRIBUTE)
   #define BOTAN_FUNC_ISA(isa) BOTAN_COMPILER_ATTRIBUTE(target(isa))
#else
   #define BOTAN_FUNC_ISA(isa)
#endif

/*
* Define BOTAN_FUNC_ISA_INLINE
*
* TODO(Botan4) Remove this
*/
#define BOTAN_FUNC_ISA_INLINE(isa) BOTAN_FUNC_ISA(isa) BOTAN_FORCE_INLINE

/*
* Define BOTAN_EARLY_INIT
*/
#if BOTAN_COMPILER_HAS_ATTRIBUTE(init_priority)
   #define BOTAN_EARLY_INIT(prio) BOTAN_COMPILER_ATTRIBUTE(init_priority(prio))
#else
   #define BOTAN_EARLY_INIT(prio) /**/
#endif

/*
* Define BOTAN_FORCE_INLINE
*/
#if !defined(BOTAN_FORCE_INLINE)

   #if BOTAN_COMPILER_HAS_ATTRIBUTE(always_inline)
      #define BOTAN_FORCE_INLINE inline BOTAN_COMPILER_ATTRIBUTE(always_inline)

   #elif defined(_MSC_VER)
      #define BOTAN_FORCE_INLINE __forceinline

   #else
      #define BOTAN_FORCE_INLINE inline
   #endif

#endif

// NOLINTEND(*-macro-usage)

namespace Botan {

/**
* This class represents an abstract data source object.
*/
class BOTAN_PUBLIC_API(2, 0) DataSource {
   public:
      /**
      * Read from the source. Moves the internal offset so that every
      * call to read will return a new portion of the source.
      *
      * @param out the byte array to write the result to
      * @param length the length of the byte array out
      * @return length in bytes that was actually read and put
      * into out
      */
      [[nodiscard]] virtual size_t read(uint8_t out[], size_t length) = 0;

      /**
      * Test whether at least n further bytes can be read
      * @param n the number of bytes required
      * @return true if at least n bytes remain
      */
      virtual bool check_available(size_t n) = 0;

      /**
      * Read from the source but do not modify the internal
      * offset. Consecutive calls to peek() will return portions of
      * the source starting at the same position.
      *
      * @param out the byte array to write the output to
      * @param length the length of the byte array out
      * @param peek_offset the offset into the stream to read at
      * @return length in bytes that was actually read and put
      * into out
      */
      [[nodiscard]] virtual size_t peek(uint8_t out[], size_t length, size_t peek_offset) const = 0;

      /**
      * Test whether the source still has data that can be read.
      * @return true if there is no more data to read, false otherwise
      */
      virtual bool end_of_data() const = 0;

      /**
      * return the id of this data source
      * @return std::string representing the id of this data source
      */
      virtual std::string id() const { return ""; }

      /**
      * Read one byte.
      * @param out the byte to read to
      * @return length in bytes that was actually read and put
      * into out
      */
      size_t read_byte(uint8_t& out);

      /**
      * Read one byte.
      *
      * Returns nullopt if no further bytes are available
      */
      std::optional<uint8_t> read_byte();

      /**
      * Peek at one byte.
      * @param out an output byte
      * @return length in bytes that was actually read and put
      * into out
      */
      size_t peek_byte(uint8_t& out) const;

      /**
      * Discard the next N bytes of the data
      * @param N the number of bytes to discard
      * @return number of bytes actually discarded
      */
      size_t discard_next(size_t N);

      /**
      * Count the bytes consumed from this source so far
      * @return number of bytes read so far
      */
      virtual size_t get_bytes_read() const = 0;

      /// Default constructor
      DataSource() = default;

      virtual ~DataSource() = default;

      // No copy available
      DataSource(const DataSource&) = delete;
      DataSource& operator=(const DataSource&) = delete;

      /// Move constructor
      DataSource(DataSource&&) = default;

      /// Move assignment
      /// @return reference to this
      DataSource& operator=(DataSource&&) = default;
};

/**
* This class represents a Memory-Based DataSource
*/
class BOTAN_PUBLIC_API(2, 0) DataSource_Memory final : public DataSource {
   public:
      /**
      * Read from the source, advancing the internal offset
      * @param buf the byte array to write the result to
      * @param length the length of the byte array buf
      * @return length in bytes that was actually read and put into buf
      */
      size_t read(uint8_t buf[], size_t length) override;

      /**
      * Read from the source without modifying the internal offset
      * @param buf the byte array to write the result to
      * @param length the length of the byte array buf
      * @param offset the offset into the stream to read at
      * @return length in bytes that was actually read and put into buf
      */
      size_t peek(uint8_t buf[], size_t length, size_t offset) const override;

      /**
      * Test whether at least n further bytes can be read
      * @param n the number of bytes required
      * @return true if at least n bytes remain
      */
      bool check_available(size_t n) override;

      /**
      * Test whether the source still has data that can be read
      * @return true if there is no more data to read, false otherwise
      */
      bool end_of_data() const override;

      /**
      * Construct a memory source that reads from a string
      * @param in the string to read from
      */
      explicit DataSource_Memory(std::string_view in);

      /**
      * Construct a memory source that reads from a byte array
      * @param in the byte array to read from
      * @param length the length of the byte array
      */
      DataSource_Memory(const uint8_t in[], size_t length) : DataSource_Memory(std::span<const uint8_t>(in, length)) {}

      /**
      * Construct a memory source that reads from a secure_vector
      * @param in the MemoryRegion to read from
      */
      explicit DataSource_Memory(secure_vector<uint8_t> in) : m_source(std::move(in)), m_offset(0) {}

      /**
      * Construct a memory source that reads from an arbitrary byte buffer
      * @param in the MemoryRegion to read from
      */
      explicit DataSource_Memory(std::span<const uint8_t> in) : m_offset(0) {
         // Guard against forming a range from a null pointer (eg an empty span)
         if(!in.empty()) {
            m_source.assign(in.begin(), in.end());
         }
      }

      /**
      * Construct a memory source that reads from a std::vector
      * @param in the MemoryRegion to read from
      */
      explicit DataSource_Memory(const std::vector<uint8_t>& in) : DataSource_Memory(std::span<const uint8_t>(in)) {}

      /**
      * Count the bytes consumed from this source so far
      * @return number of bytes read so far
      */
      size_t get_bytes_read() const override { return m_offset; }

   private:
      secure_vector<uint8_t> m_source;
      size_t m_offset;
};

/**
* This class represents a Stream-Based DataSource.
*/
class BOTAN_PUBLIC_API(2, 0) DataSource_Stream final : public DataSource {
   public:
      /**
      * Read from the source, advancing the internal offset
      * @param buf the byte array to write the result to
      * @param length the length of the byte array buf
      * @return length in bytes that was actually read and put into buf
      */
      size_t read(uint8_t buf[], size_t length) override;

      /**
      * Read from the source without modifying the internal offset
      * @param buf the byte array to write the result to
      * @param length the length of the byte array buf
      * @param offset the offset into the stream to read at
      * @return length in bytes that was actually read and put into buf
      */
      size_t peek(uint8_t buf[], size_t length, size_t offset) const override;

      /**
      * Test whether at least n further bytes can be read
      * @param n the number of bytes required
      * @return true if at least n bytes remain
      */
      bool check_available(size_t n) override;

      /**
      * Test whether the source still has data that can be read
      * @return true if there is no more data to read, false otherwise
      */
      bool end_of_data() const override;

      /**
      * Return the id of this data source
      * @return a string representing the id of this data source
      */
      std::string id() const override;

      /**
      * Construct a Stream-Based DataSource from an istream
      * @param in the stream to read from
      * @param id an identifier for this source, used in error messages
      */
      BOTAN_FUTURE_EXPLICIT DataSource_Stream(std::istream& in, std::string_view id = "<std::istream>");

#if defined(BOTAN_TARGET_OS_HAS_FILESYSTEM)
      /**
      * Construct a Stream-Based DataSource from filesystem path
      * @param filename the path to the file
      * @param use_binary whether to treat the file as binary or not
      */
      BOTAN_FUTURE_EXPLICIT DataSource_Stream(std::string_view filename, bool use_binary = false);
#endif

      // Stream data sources are not copyable or moveable
      DataSource_Stream(const DataSource_Stream&) = delete;
      DataSource_Stream(DataSource_Stream&&) = delete;
      DataSource_Stream& operator=(const DataSource_Stream&) = delete;
      DataSource_Stream& operator=(DataSource_Stream&&) = delete;

      ~DataSource_Stream() override;

      /**
      * Count the bytes consumed from this source so far
      * @return number of bytes read so far
      */
      size_t get_bytes_read() const override { return m_total_read; }

   private:
      const std::string m_identifier;

      std::unique_ptr<std::istream> m_source_memory;
      std::istream& m_source;
      size_t m_total_read;
};

}  // namespace Botan

namespace Botan {

/**
* Abstract interface to a SQL database
*/
class BOTAN_PUBLIC_API(2, 0) SQL_Database /* NOLINT(*-special-member-functions) */ {
   public:
      /**
      * An error occurred while interacting with the database
      */
      class BOTAN_PUBLIC_API(2, 0) SQL_DB_Error final : public Exception {
         public:
            /**
            * Create a SQL_DB_Error
            * @param what a description of the failure
            */
            explicit SQL_DB_Error(std::string_view what) : Exception("SQL database", what), m_rc(0) {}

            /**
            * Create a SQL_DB_Error
            * @param what a description of the failure
            * @param rc the database specific result code
            */
            SQL_DB_Error(std::string_view what, int rc) : Exception("SQL database", what), m_rc(rc) {}

            /**
            * Return the error type of this exception
            * @return the error type of this exception
            */
            ErrorType error_type() const noexcept override { return ErrorType::DatabaseError; }

            /**
            * Return the database specific result code
            * @return the result code passed at construction, or 0
            */
            int error_code() const noexcept override { return m_rc; }

         private:
            int m_rc;
      };

      /**
      * A prepared SQL statement
      */
      class BOTAN_PUBLIC_API(2, 0) Statement /* NOLINT(*-special-member-functions) */ {
         public:
            /**
            * Bind a string to a statement parameter
            * @param column the 1-based index of the parameter
            * @param str the value to bind
            */
            virtual void bind(int column, std::string_view str) = 0;

            /**
            * Bind an integer to a statement parameter
            * @param column the 1-based index of the parameter
            * @param i the value to bind
            */
            virtual void bind(int column, size_t i) = 0;

            /**
            * Bind a timestamp to a statement parameter
            * @param column the 1-based index of the parameter
            * @param time the value to bind
            */
            virtual void bind(int column, std::chrono::system_clock::time_point time) = 0;

            /**
            * Bind a blob to a statement parameter
            * @param column the 1-based index of the parameter
            * @param blob the value to bind
            */
            virtual void bind(int column, const std::vector<uint8_t>& blob) = 0;

            /**
            * Bind a blob to a statement parameter
            * @param column the 1-based index of the parameter
            * @param data the value to bind
            * @param len length of data in bytes
            */
            virtual void bind(int column, const uint8_t* data, size_t len) = 0;

            /**
            * Bind SQL NULL to a statement parameter
            * @param column the 1-based index of the parameter
            */
            virtual void bind_null(int column) = 0;

            /**
            * Read a blob from the current result row
            * @param column the 0-based index of the column
            * @return the blob value, valid until the next call to step
            */
            virtual std::span<const uint8_t> get_blob(int column) = 0;

            /**
            * Read a string from the current result row
            * @param column the 0-based index of the column
            * @return the string value, or nullopt if the column value was NULL
            */
            virtual std::optional<std::string> get_str(int column) = 0;

            /**
            * Read an integer from the current result row
            * @param column the 0-based index of the column
            * @return the integer value
            */
            virtual size_t get_size_t(int column) = 0;

            /**
            * Run the statement to completion
            * @return the number of result rows which were stepped over
            */
            virtual size_t spin() = 0;

            /**
            * Advance to the next result row
            * @return true if a row is available, false once the results are exhausted
            */
            virtual bool step() = 0;

            virtual ~Statement() = default;
      };

      /**
      * Create a new statement for execution.
      * Use ?1, ?2, ?3, etc for parameters to set later with bind
      *
      * @param base_sql the SQL text of the statement
      * @return the prepared statement
      */
      virtual std::shared_ptr<Statement> new_statement(std::string_view base_sql) const = 0;

      /**
      * Prepare a "SELECT <columns> FROM <table> [WHERE <where>] [LIMIT <limit>]"
      * statement. `where` is the body of the WHERE clause (e.g.
      * "id = ?1 AND name = ?2"); pass an empty string for no WHERE clause. Use
      * ?1, ?2, ... for bound parameters. Virtual so backends can override if helpful.
      *
      * @param columns the columns to select
      * @param table the table to select from
      * @param where the body of the WHERE clause, or empty for no WHERE clause
      * @param limit the maximum number of rows, or nullopt for no limit
      * @return the prepared statement
      */
      virtual std::shared_ptr<Statement> select(std::string_view columns,
                                                std::string_view table,
                                                std::string_view where = {},
                                                std::optional<size_t> limit = std::nullopt) const;

      /**
      * Prepare an upsert (insert-or-replace) statement for the given columns of
      * the given table. The returned statement expects placeholders ?1..?N
      * bound in the order the columns were given. The list must include every
      * column of the table's primary key; backends that need the key/value
      * distinction (e.g. Postgres ON CONFLICT) derive it by introspecting the
      * schema.
      *
      * @param table the table to upsert into
      * @param columns the columns to write, in placeholder order
      * @return the prepared statement
      */
      virtual std::shared_ptr<Statement> upsert(std::string_view table,
                                                std::initializer_list<std::string_view> columns) const = 0;

      /**
      * Count the rows of a table
      * @param table_name the table to count
      * @return the number of rows in the table
      */
      virtual size_t row_count(std::string_view table_name) = 0;

      /**
      * The supported column types
      */
      enum class Column_Type : uint8_t {
         Blob,
         String,
         Integer,
      };

      /**
      * The name, type and constraints of one column of a table
      */
      class Column {
         public:
            /**
            * Declare a column
            * @param name the name of the column
            * @param type the type of the column
            */
            Column(std::string name, Column_Type type) : m_name(std::move(name)), m_type(type) {}

            /**
            * Mark this column as part of the primary key
            * @return reference to this
            */
            Column& primary_key() {
               m_primary_key = true;
               return *this;
            }

            /**
            * Mark this column as NOT NULL
            * @return reference to this
            */
            Column& not_null() {
               m_not_null = true;
               return *this;
            }

            /**
            * Mark this column as UNIQUE
            * @return reference to this
            */
            Column& unique() {
               m_unique = true;
               return *this;
            }

            /**
            * Query the column name
            * @return the name of the column
            */
            const std::string& name() const { return m_name; }

            /**
            * Query the column type
            * @return the type of the column
            */
            Column_Type type() const { return m_type; }

            /**
            * Query whether this column is part of the primary key
            * @return true if primary_key was called
            */
            bool is_primary_key() const { return m_primary_key; }

            /**
            * Query whether this column is NOT NULL
            * @return true if not_null was called
            */
            bool is_not_null() const { return m_not_null; }

            /**
            * Query whether this column is UNIQUE
            * @return true if unique was called
            */
            bool is_unique() const { return m_unique; }

         private:
            std::string m_name;
            Column_Type m_type;
            bool m_primary_key = false;
            bool m_not_null = false;
            bool m_unique = false;
      };

      /**
      * The name and columns of a table, used with create_table
      */
      class Table_Schema {
         public:
            /**
            * Declare a table
            * @param name the name of the table
            * @param columns the columns of the table
            */
            Table_Schema(std::string name, std::vector<Column> columns) :
                  m_name(std::move(name)), m_columns(std::move(columns)) {}

            /**
            * Only create the table if it does not already exist
            * @return reference to this
            */
            Table_Schema& if_not_exists() {
               m_if_not_exists = true;
               return *this;
            }

            /**
            * Query the table name
            * @return the name of the table
            */
            const std::string& name() const { return m_name; }

            /**
            * Query the columns of the table
            * @return the columns of the table
            */
            const std::vector<Column>& columns() const { return m_columns; }

            /**
            * Query whether creation is conditional
            * @return true if if_not_exists was called
            */
            bool is_if_not_exists() const { return m_if_not_exists; }

         private:
            std::string m_name;
            std::vector<Column> m_columns;
            bool m_if_not_exists = false;
      };

      /**
      * Create a table
      * @param schema the name and columns of the table to create
      */
      virtual void create_table(const Table_Schema& schema) = 0;

      /**
      * Count the rows modified by the most recently executed statement
      * @return the number of rows inserted, updated or deleted
      */
      virtual size_t rows_changed_by_last_statement() = 0;

      /**
      * Prepare and run a statement to completion
      * @param sql the SQL text to execute
      * @return the number of result rows which were stepped over
      */
      virtual size_t exec(std::string_view sql) { return new_statement(sql)->spin(); }

      /**
      * Query whether this database may be used from multiple threads
      * @return true if the implementation is threadsafe
      */
      virtual bool is_threadsafe() const { return false; }

      /**
      * Return true if the given name seems to be valid as the name for a table
      *
      * Default implementation accepts non-empty [a-zA-Z0-9_]
      *
      * @param table the name to check
      * @return true if the name is acceptable as a table name
      */
      virtual bool is_valid_table_name(std::string_view table) const;

      virtual ~SQL_Database() = default;
};

}  // namespace Botan

namespace Botan {

/**
* This class represents hash function (message digest) objects
*/
class BOTAN_PUBLIC_API(2, 0) HashFunction : public Buffered_Computation {
   public:
      /**
      * Create an instance based on a name, or return null if the
      * algo/provider combination cannot be found. If provider is
      * empty then best available is chosen.
      */
      static std::unique_ptr<HashFunction> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to use
      * Throws Lookup_Error if not found.
      */
      static std::unique_ptr<HashFunction> create_or_throw(std::string_view algo_spec, std::string_view provider = "");

      /**
      * List the providers available for a given hash
      * @return list of available providers for this algorithm, empty if not available
      * @param algo_spec algorithm name
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Return the name of the provider implementing this object
      * @return provider information about this implementation. Default is "base",
      * might also return "sse2", "avx2", "openssl", or some other arbitrary string.
      */
      virtual std::string provider() const { return "base"; }

      /**
      * Reset the state.
      */
      virtual void clear() = 0;

      /**
      * Return the name of this hash function
      * @return the hash function name
      */
      virtual std::string name() const = 0;

      /**
      * Return the internal block size of this hash function
      * @return hash block size as defined for this algorithm
      */
      virtual size_t hash_block_size() const { return 0; }

      /**
      * Return an estimate, in bits, of the security level of this hash
      * function, with respect to collision resistance. For most hashes this is
      * simply half the output length, matching the generic birthday attack.
      * It is lower for hash functions with a known collision attack, and zero
      * for checksums and any hash where finding collisions is trivial.
      */
      virtual size_t security_level() const { return 4 * output_length(); }

      /**
      * Return a new hash object with the same state as *this. This
      * allows computing the hash of several messages with a common
      * prefix more efficiently than would otherwise be possible.
      *
      * This function should be called `clone` but that was already
      * used for the case of returning an uninitialized object.
      * @return new hash object
      */
      virtual std::unique_ptr<HashFunction> copy_state() const = 0;

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      virtual std::unique_ptr<HashFunction> new_object() const = 0;

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      HashFunction* clone() const { return this->new_object().release(); }
};

}  // namespace Botan

namespace Botan {

/**
* Perform hex encoding
* @param output an array of at least input_length*2 bytes
* @param input is some binary data
* @param input_length length of input in bytes
* @param uppercase should output be upper or lower case?
*/
void BOTAN_PUBLIC_API(2, 0)
   hex_encode(char output[], const uint8_t input[], size_t input_length, bool uppercase = true);

/**
* Perform hex encoding
* @param input some input
* @param input_length length of input in bytes
* @param uppercase should output be upper or lower case?
* @return hexadecimal representation of input
*/
std::string BOTAN_PUBLIC_API(2, 0) hex_encode(const uint8_t input[], size_t input_length, bool uppercase = true);

/**
* Perform hex encoding
* @param input some input
* @param uppercase should output be upper or lower case?
* @return hexadecimal representation of input
*/
inline std::string hex_encode(std::span<const uint8_t> input, bool uppercase = true) {
   return hex_encode(input.data(), input.size(), uppercase);
}

/**
* Perform hex decoding
* @param output an array of at least input_length/2 bytes
* @param input some hex input
* @param input_length length of input in bytes
* @param input_consumed is an output parameter which says how many
*        bytes of input were actually consumed. If less than
*        input_length, then the range input[consumed:length]
*        should be passed in later along with more input.
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 0)
   hex_decode(uint8_t output[], const char input[], size_t input_length, size_t& input_consumed, bool ignore_ws = true);

/**
* Perform hex decoding
* @param output an array of at least input_length/2 bytes
* @param input some hex input
* @param input_length length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(2, 0)
   hex_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform hex decoding
* @param output an array of at least input_length/2 bytes
* @param input some hex input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(3, 0) hex_decode(uint8_t output[], std::string_view input, bool ignore_ws = true);

/**
* Perform hex decoding
* @param output a contiguous byte buffer of at least input_length/2 bytes
* @param input some hex input
* @param ignore_ws ignore whitespace on input; if false, throw an
*                  exception if whitespace is encountered
* @return number of bytes written to output
*/
size_t BOTAN_PUBLIC_API(3, 0) hex_decode(std::span<uint8_t> output, std::string_view input, bool ignore_ws = true);

/**
* Perform hex decoding
* @param input some hex input
* @param input_length the length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded hex output
*/
std::vector<uint8_t> BOTAN_PUBLIC_API(2, 0) hex_decode(const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform hex decoding
* @param input some hex input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded hex output
*/
std::vector<uint8_t> BOTAN_PUBLIC_API(3, 0) hex_decode(std::string_view input, bool ignore_ws = true);

/**
* Perform hex decoding
* @param input some hex input
* @param input_length the length of input in bytes
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded hex output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 0)
   hex_decode_locked(const char input[], size_t input_length, bool ignore_ws = true);

/**
* Perform hex decoding
* @param input some hex input
* @param ignore_ws ignore whitespace on input; if false, throw an
                   exception if whitespace is encountered
* @return decoded hex output
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(3, 0) hex_decode_locked(std::string_view input, bool ignore_ws = true);

}  // namespace Botan

#if defined(BOTAN_TARGET_OS_HAS_THREADS)
   #include <mutex>
#endif

namespace Botan {

#if defined(BOTAN_TARGET_OS_HAS_THREADS)

/// The mutex type used by the library
using mutex_type = std::mutex;

/// The recursive mutex type used by the library
using recursive_mutex_type = std::recursive_mutex;

template <typename T>
using lock_guard_type = std::scoped_lock<T>;

#else

// No threads

class noop_mutex final {
   public:
      void lock() {}

      void unlock() {}
};

using mutex_type = noop_mutex;
using recursive_mutex_type = noop_mutex;

template <typename Mutex>
class lock_guard final {
   public:
      explicit lock_guard(Mutex& m) : m_mutex(m) { m_mutex.lock(); }

      ~lock_guard() { m_mutex.unlock(); }

      lock_guard(const lock_guard& other) = delete;
      lock_guard& operator=(const lock_guard& other) = delete;

   private:
      Mutex& m_mutex;
};

template <typename T>
using lock_guard_type = lock_guard<T>;

#endif

}  // namespace Botan

namespace Botan {

/**
* Inherited by RNGs which maintain in-process state, like HMAC_DRBG.
* On Unix these RNGs are vulnerable to problems with fork, where the
* RNG state is duplicated, and the parent and child process RNGs will
* produce identical output until one of them reseeds. Stateful_RNG
* reseeds itself whenever a fork is detected, or after a set number of
* bytes have been output.
*
* Not implemented by RNGs which access an external RNG, such as the
* system PRNG or a hardware RNG.
*/
class BOTAN_PUBLIC_API(2, 0) Stateful_RNG : public RandomNumberGenerator {
   public:
      /**
      * Create a Stateful_RNG which reseeds from both an RNG and entropy sources
      *
      * @param rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      Stateful_RNG(RandomNumberGenerator& rng, Entropy_Sources& entropy_sources, size_t reseed_interval) :
            m_underlying_rng(&rng), m_entropy_sources(&entropy_sources), m_reseed_interval(reseed_interval) {}

      /**
      * Create a Stateful_RNG which reseeds from another RNG
      *
      * @param rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      Stateful_RNG(RandomNumberGenerator& rng, size_t reseed_interval) :
            m_underlying_rng(&rng), m_reseed_interval(reseed_interval) {}

      /**
      * Create a Stateful_RNG which reseeds from entropy sources
      *
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed
      */
      Stateful_RNG(Entropy_Sources& entropy_sources, size_t reseed_interval) :
            m_entropy_sources(&entropy_sources), m_reseed_interval(reseed_interval) {}

      /**
      * In this case, automatic reseeding is impossible
      */
      Stateful_RNG() : m_reseed_interval(0) {}

      /**
      * Consume this input and mark the RNG as initialized regardless
      * of the length of the input or the current seeded state of
      * the RNG.
      */
      void initialize_with(std::span<const uint8_t> input);

      /**
      * Consume this input and mark the RNG as initialized regardless
      * of the length of the input or the current seeded state of the RNG.
      * @param input the seed material
      * @param length the number of bytes in input
      */
      void initialize_with(const uint8_t input[], size_t length) { this->initialize_with(std::span(input, length)); }

      /**
      * Test whether this RNG has been seeded
      * @return true if this RNG is seeded and ready for use
      */
      bool is_seeded() const final;

      /**
      * Test whether this RNG accepts externally provided input
      * @return false if this RNG is known to ignore provided inputs
      */
      bool accepts_input() const final { return true; }

      /**
      * Mark state as requiring a reseed on next use
      */
      void force_reseed();

      /**
      * Reseed this RNG from another RNG
      * @param rng the RNG to draw seed material from
      * @param poll_bits the number of bits to collect
      */
      void reseed_from_rng(RandomNumberGenerator& rng, size_t poll_bits = RandomNumberGenerator::DefaultPollBits) final;

      /**
      * Poll provided sources for up to poll_bits bits of entropy.
      * Returns estimate of the number of bits collected.
      */
      size_t reseed_from_sources(Entropy_Sources& srcs,
                                 size_t poll_bits = RandomNumberGenerator::DefaultPollBits) final;

      /**
      * Return the security level of this DRBG
      * @return intended security level of this DRBG
      */
      virtual size_t security_level() const = 0;

      /**
      * Return the largest number of bytes this DRBG will produce per request
      * Some DRBGs have a notion of the maximum number of bytes per
      * request.  Longer requests (to randomize) will be treated as
      * multiple requests, and may initiate reseeding multiple times,
      * depending on the values of max_number_of_bytes_per_request and
      * reseed_interval(). This function returns zero if the RNG in
      * question does not have such a notion.
      *
      * @return max number of bytes per request (or zero)
      */
      virtual size_t max_number_of_bytes_per_request() const = 0;

      /**
      * Return how many requests may be made before automatic reseeding
      * @return the reseed interval, or zero if automatic reseeding is disabled
      */
      size_t reseed_interval() const { return m_reseed_interval; }

      /**
      * Clear all internally held values of this RNG
      */
      void clear() final;

   protected:
      /**
      * Reseed if the reseed interval has elapsed, or throw if unseeded
      */
      void reseed_check();

      /**
      * Generate output, incorporating the provided input
      * @param output the buffer to fill
      * @param input additional input to incorporate
      */
      virtual void generate_output(std::span<uint8_t> output, std::span<const uint8_t> input) = 0;

      /**
      * Incorporate the provided input into the RNG state
      * @param input the seed material
      */
      virtual void update(std::span<const uint8_t> input) = 0;

      /**
      * Clear the subclass specific portion of the RNG state
      */
      virtual void clear_state() = 0;

   private:
      void generate_batched_output(std::span<uint8_t> output, std::span<const uint8_t> input);

      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> input) final;

      void reset_reseed_counter();

      mutable recursive_mutex_type m_mutex;

      // A non-owned and possibly null pointer to shared RNG
      RandomNumberGenerator* m_underlying_rng = nullptr;

      // A non-owned and possibly null pointer to a shared Entropy_Source
      Entropy_Sources* m_entropy_sources = nullptr;

      const size_t m_reseed_interval;
      uint32_t m_last_pid = 0;

      /*
      * Set to 1 after a successful seeding, then incremented.  Reset
      * to 0 by clear() or a fork. This logic is used even if
      * automatic reseeding is disabled (via m_reseed_interval = 0)
      */
      size_t m_reseed_counter = 0;
};

}  // namespace Botan

namespace Botan {

class MessageAuthenticationCode;
class Entropy_Sources;

/**
* HMAC_DRBG from NIST SP800-90A
*/
class BOTAN_PUBLIC_API(2, 0) HMAC_DRBG final : public Stateful_RNG {
   public:
      /**
      * Initialize an HMAC_DRBG instance with the given MAC as PRF (normally HMAC)
      *
      * Automatic reseeding is disabled completely, as it has no access to
      * any source for seed material.
      *
      * If a fork is detected, the RNG will be unable to reseed itself
      * in response. In this case, an exception will be thrown rather
      * than generating duplicated output.
      */
      explicit HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf);

      /**
      * Constructor taking a string for the hash
      */
      explicit HMAC_DRBG(std::string_view hmac_hash);

      /**
      * Initialize an HMAC_DRBG instance with the given MAC as PRF (normally HMAC)
      *
      * Automatic reseeding from @p underlying_rng will take place after
      * @p reseed_interval many requests or after a fork was detected.
      *
      * @param prf MAC to use as a PRF
      * @param underlying_rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed (max. 2^24)
      * @param max_number_of_bytes_per_request requests that are in size higher
      * than max_number_of_bytes_per_request are treated as if multiple single
      * requests of max_number_of_bytes_per_request size had been made.
      * In theory SP 800-90A requires that we reject any request for a DRBG
      * output longer than max_number_of_bytes_per_request. To avoid inconveniencing
      * the caller who wants an output larger than max_number_of_bytes_per_request,
      * instead treat these requests as if multiple requests of
      * max_number_of_bytes_per_request size had been made. NIST requires for
      * HMAC_DRBG that every implementation set a value no more than 2**19 bits
      * (or 64 KiB). Together with @p reseed_interval = 1 you can enforce that for
      * example every 512 bit automatic reseeding occurs.
      */
      HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                RandomNumberGenerator& underlying_rng,
                size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval,
                size_t max_number_of_bytes_per_request = 64 * 1024);

      /**
      * Initialize an HMAC_DRBG instance with the given MAC as PRF (normally HMAC)
      *
      * Automatic reseeding from @p entropy_sources will take place after
      * @p reseed_interval many requests or after a fork was detected.
      *
      * @param prf MAC to use as a PRF
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed (max. 2^24)
      * @param max_number_of_bytes_per_request requests that are in size higher
      * than max_number_of_bytes_per_request are treated as if multiple single
      * requests of max_number_of_bytes_per_request size had been made.
      * In theory SP 800-90A requires that we reject any request for a DRBG
      * output longer than max_number_of_bytes_per_request. To avoid inconveniencing
      * the caller who wants an output larger than max_number_of_bytes_per_request,
      * instead treat these requests as if multiple requests of
      * max_number_of_bytes_per_request size had been made. NIST requires for
      * HMAC_DRBG that every implementation set a value no more than 2**19 bits
      * (or 64 KiB). Together with @p reseed_interval = 1 you can enforce that for
      * example every 512 bit automatic reseeding occurs.
      */
      HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                Entropy_Sources& entropy_sources,
                size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval,
                size_t max_number_of_bytes_per_request = 64 * 1024);

      /**
      * Initialize an HMAC_DRBG instance with the given MAC as PRF (normally HMAC)
      *
      * Automatic reseeding from @p underlying_rng and @p entropy_sources
      * will take place after @p reseed_interval many requests or after
      * a fork was detected.
      *
      * @param prf MAC to use as a PRF
      * @param underlying_rng is a reference to some RNG which will be used
      * to perform the periodic reseeding
      * @param entropy_sources will be polled to perform reseeding periodically
      * @param reseed_interval specifies a limit of how many times
      * the RNG will be called before automatic reseeding is performed (max. 2^24)
      * @param max_number_of_bytes_per_request requests that are in size higher
      * than max_number_of_bytes_per_request are treated as if multiple single
      * requests of max_number_of_bytes_per_request size had been made.
      * In theory SP 800-90A requires that we reject any request for a DRBG
      * output longer than max_number_of_bytes_per_request. To avoid inconveniencing
      * the caller who wants an output larger than max_number_of_bytes_per_request,
      * instead treat these requests as if multiple requests of
      * max_number_of_bytes_per_request size had been made. NIST requires for
      * HMAC_DRBG that every implementation set a value no more than 2**19 bits
      * (or 64 KiB). Together with @p reseed_interval = 1 you can enforce that for
      * example every 512 bit automatic reseeding occurs.
      */
      HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                RandomNumberGenerator& underlying_rng,
                Entropy_Sources& entropy_sources,
                size_t reseed_interval = RandomNumberGenerator::DefaultReseedInterval,
                size_t max_number_of_bytes_per_request = 64 * 1024);

      ~HMAC_DRBG() override;

      HMAC_DRBG(const HMAC_DRBG& rng) = delete;
      HMAC_DRBG& operator=(const HMAC_DRBG& rng) = delete;

      HMAC_DRBG(HMAC_DRBG&& rng) = delete;
      HMAC_DRBG& operator=(HMAC_DRBG&& rng) = delete;

      /**
      * Return the name of this RNG type
      * @return the name of this RNG type
      */
      std::string name() const override;

      /**
      * Return the security level of this DRBG
      * @return the estimated security level in bits
      */
      size_t security_level() const override;

      /**
      * Return the largest number of bytes this DRBG will produce per request
      * @return the maximum request size in bytes
      */
      size_t max_number_of_bytes_per_request() const override { return m_max_number_of_bytes_per_request; }

   private:
      void update(std::span<const uint8_t> input) override;

      void generate_output(std::span<uint8_t> output, std::span<const uint8_t> input) override;

      void clear_state() override;

      std::unique_ptr<MessageAuthenticationCode> m_mac;
      secure_vector<uint8_t> m_V;
      secure_vector<uint8_t> m_T;
      const size_t m_max_number_of_bytes_per_request;
      const size_t m_security_level;
};

}  // namespace Botan

namespace Botan {

/**
* Key Derivation Function
*/
class BOTAN_PUBLIC_API(2, 0) KDF /* NOLINT(*-special-member-functions*) */ {
   public:
      virtual ~KDF() = default;

      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to choose
      * @return a null pointer if the algo/provider combination cannot be found
      */
      static std::unique_ptr<KDF> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name, or throw if the
      * algo/provider combination cannot be found. If provider is
      * empty then best available is chosen.
      */
      static std::unique_ptr<KDF> create_or_throw(std::string_view algo_spec, std::string_view provider = "");

      /**
      * List the providers available for a given KDF
      * @return list of available providers for this algorithm, empty if not available
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Return the name of this KDF
      * @return KDF name
      */
      virtual std::string name() const = 0;

      /**
      * Derive a key
      * @param key buffer holding the derived key, must be of length key_len
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param secret_len size of secret in bytes
      * @param salt a diversifier
      * @param salt_len size of salt in bytes
      * @param label purpose for the derived keying material
      * @param label_len size of label in bytes
      */
      BOTAN_DEPRECATED("Use KDF::derive_key")
      void kdf(uint8_t key[],
               size_t key_len,
               const uint8_t secret[],
               size_t secret_len,
               const uint8_t salt[],
               size_t salt_len,
               const uint8_t label[],
               size_t label_len) const {
         derive_key({key, key_len}, {secret, secret_len}, {salt, salt_len}, {label, label_len});
      }

      /**
      * Derive a key
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param secret_len size of secret in bytes
      * @param salt a diversifier
      * @param salt_len size of salt in bytes
      * @param label purpose for the derived keying material
      * @param label_len size of label in bytes
      * @return the derived key
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      BOTAN_DEPRECATED("Use std::span or std::string_view overloads")
      T derive_key(size_t key_len,
                   const uint8_t secret[],
                   size_t secret_len,
                   const uint8_t salt[],
                   size_t salt_len,
                   const uint8_t label[] = nullptr,
                   size_t label_len = 0) const {
         return derive_key<T>(key_len, {secret, secret_len}, {salt, salt_len}, {label, label_len});
      }

      /**
      * Derive a key
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T derive_key(size_t key_len,
                   std::span<const uint8_t> secret,
                   std::string_view salt = "",
                   std::string_view label = "") const {
         return derive_key<T>(key_len, secret, _as_span(salt), _as_span(label));
      }

      /**
      * Derive a key
      * @param key the output buffer for the to-be-derived key
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      */
      void derive_key(std::span<uint8_t> key,
                      std::span<const uint8_t> secret,
                      std::span<const uint8_t> salt,
                      std::span<const uint8_t> label) const {
         perform_kdf(key, secret, salt, label);
      }

      /**
      * Derive a key
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T derive_key(size_t key_len,
                   std::span<const uint8_t> secret,
                   std::span<const uint8_t> salt,
                   std::span<const uint8_t> label) const {
         T key(key_len);
         perform_kdf(key, secret, salt, label);
         return key;
      }

      /**
      * Derive a key
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param salt_len size of salt in bytes
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      BOTAN_DEPRECATED("Use std::span or std::string_view overloads")
      T derive_key(size_t key_len,
                   std::span<const uint8_t> secret,
                   const uint8_t salt[],
                   size_t salt_len,
                   std::string_view label = "") const {
         return derive_key<T>(key_len, secret, {salt, salt_len}, _as_span(label));
      }

      /**
      * Derive a key
      * @param key_len the desired output length in bytes
      * @param secret the secret input
      * @param secret_len size of secret in bytes
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      BOTAN_DEPRECATED("Use std::span or std::string_view overloads")
      T derive_key(size_t key_len,
                   const uint8_t secret[],
                   size_t secret_len,
                   std::string_view salt = "",
                   std::string_view label = "") const {
         return derive_key<T>(key_len, {secret, secret_len}, _as_span(salt), _as_span(label));
      }

      /**
      * Derive a key
      * @tparam key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <size_t key_len>
      std::array<uint8_t, key_len> derive_key(std::span<const uint8_t> secret,
                                              std::span<const uint8_t> salt = {},
                                              std::span<const uint8_t> label = {}) {
         std::array<uint8_t, key_len> key{};
         perform_kdf(key, secret, salt, label);
         return key;
      }

      /**
      * Derive a key
      * @tparam key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <size_t key_len>
      std::array<uint8_t, key_len> derive_key(std::span<const uint8_t> secret,
                                              std::span<const uint8_t> salt = {},
                                              std::string_view label = "") {
         return derive_key<key_len>(secret, salt, _as_span(label));
      }

      /**
      * Derive a key
      * @tparam key_len the desired output length in bytes
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      * @return the derived key
      */
      template <size_t key_len>
      std::array<uint8_t, key_len> derive_key(std::span<const uint8_t> secret,
                                              std::string_view salt = "",
                                              std::string_view label = "") {
         return derive_key<key_len>(secret, _as_span(salt), _as_span(label));
      }

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      virtual std::unique_ptr<KDF> new_object() const = 0;

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      KDF* clone() const { return this->new_object().release(); }

   protected:
      /**
      * Internal customization point for subclasses
      *
      * The byte size of the @p key span is the number of bytes to be produced
      * by the concrete key derivation function.
      *
      * @param key the output buffer for the to-be-derived key
      * @param secret the secret input
      * @param salt a diversifier
      * @param label purpose for the derived keying material
      */
      virtual void perform_kdf(std::span<uint8_t> key,
                               std::span<const uint8_t> secret,
                               std::span<const uint8_t> salt,
                               std::span<const uint8_t> label) const = 0;

   private:
      static std::span<const uint8_t> _as_span(std::string_view s);
};

/**
* Factory method for KDF (key derivation function)
* @param algo_spec the name of the KDF to create
* @return pointer to newly allocated object of that type
*
* Prefer KDF::create
*/
BOTAN_DEPRECATED("Use KDF::create")

inline KDF* get_kdf(std::string_view algo_spec) {
   if(algo_spec == "Raw") {
      return nullptr;
   }

   return KDF::create_or_throw(algo_spec).release();
}

}  // namespace Botan

namespace Botan {

/**
* This class represents Message Authentication Code (MAC) objects.
*/
class BOTAN_PUBLIC_API(2, 0) MessageAuthenticationCode : public Buffered_Computation,
                                                         public SymmetricAlgorithm {
   public:
      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to use
      * @return a null pointer if the algo/provider combination cannot be found
      */
      static std::unique_ptr<MessageAuthenticationCode> create(std::string_view algo_spec,
                                                               std::string_view provider = "");

      /**
      * Create an instance based on a name, throwing if it is not available
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to use
      * Throws a Lookup_Error if algo/provider combination cannot be found
      */
      static std::unique_ptr<MessageAuthenticationCode> create_or_throw(std::string_view algo_spec,
                                                                        std::string_view provider = "");

      /**
      * List the providers available for a given MAC
      * @return list of available providers for this algorithm, empty if not available
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Prepare for processing a message under the specified nonce
      * Calling start() abandons any partial message and begins a new one.
      *
      * Most MACs neither require nor support a nonce; for these algorithms
      * calling start() is optional and calling it with anything other than
      * an empty string is an error. One MAC which *requires* a per-message
      * nonce be specified is GMAC.
      *
      * Default implementation simply rejects all non-empty nonces
      * since most hash/MAC algorithms do not support randomization
      *
      * @param nonce the message nonce bytes
      */
      void start(std::span<const uint8_t> nonce) { start_msg(nonce); }

      /**
      * Begin processing a message.
      * @param nonce the per message nonce
      * @param nonce_len length of nonce
      */
      void start(const uint8_t nonce[], size_t nonce_len) { start_msg({nonce, nonce_len}); }

      /**
      * Begin processing a message.
      */
      void start() { return start_msg({}); }

      /**
      * Verify a MAC.
      * @param in the MAC to verify as a byte array
      * @param length the length of param in
      * @return true if the MAC is valid, false otherwise
      */
      bool verify_mac(const uint8_t in[], size_t length) { return verify_mac_result({in, length}); }

      /**
      * Verify a MAC.
      * @param in the MAC to verify as a byte array
      * @return true if the MAC is valid, false otherwise
      */
      bool verify_mac(std::span<const uint8_t> in) { return verify_mac_result(in); }

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      virtual std::unique_ptr<MessageAuthenticationCode> new_object() const = 0;

      /**
      * Get a new object representing the same algorithm as *this
      */
      MessageAuthenticationCode* clone() const { return this->new_object().release(); }

      /**
      * Return the name of the provider implementing this object
      * @return provider information about this implementation. Default is "base",
      * might also return "sse2", "avx2", "openssl", or some other arbitrary string.
      */
      virtual std::string provider() const { return "base"; }

      /**
      * @return if a fresh key must be set for each message that is processed.
      *
      * This is required for certain polynomial-based MACs which are insecure
      * if a key is ever reused for two different messages.
      */
      virtual bool fresh_key_required_per_message() const { return false; }

   protected:
      /**
      * Prepare for processing a message under the specified nonce
      *
      * This should reset any state associated with any message currently being
      * processed.
      */
      virtual void start_msg(std::span<const uint8_t> nonce) = 0;

      /**
      * Verify the MACs final result
      */
      virtual bool verify_mac_result(std::span<const uint8_t> in);
};

/**
* A shorter alias for MessageAuthenticationCode
*/
typedef MessageAuthenticationCode MAC;

}  // namespace Botan

BOTAN_FUTURE_INTERNAL_HEADER(range_concepts.h)

namespace Botan::ranges {

/**
 * Models a std::ranges::contiguous_range that (optionally) restricts its
 * value_type to ValueT. In other words: a stretch of contiguous memory of
 * a certain type (optional ValueT).
 */
template <typename T, typename ValueT = std::ranges::range_value_t<T>>
concept contiguous_range = std::ranges::contiguous_range<T> && std::same_as<ValueT, std::ranges::range_value_t<T>>;

/**
 * Models a std::ranges::contiguous_range that satisfies
 * std::ranges::output_range with an arbitrary value_type. In other words: a
 * stretch of contiguous memory of a certain type (optional ValueT) that can be
 * written to.
 */
template <typename T, typename ValueT = std::ranges::range_value_t<T>>
concept contiguous_output_range = contiguous_range<T, ValueT> && std::ranges::output_range<T, ValueT>;

/**
 * Models a range that can be turned into a std::span<>. Typically, this is some
 * form of ranges::contiguous_range.
 */
template <typename T>
concept spanable_range = std::constructible_from<std::span<const std::ranges::range_value_t<T>>, T>;

/**
 * Models a range that can be turned into a std::span<> with a static extent.
 * Typically, this is a std::array or a std::span derived from an array.
 */
// clang-format off
template <typename T>
concept statically_spanable_range = spanable_range<T> &&
                                    decltype(std::span{std::declval<T&>()})::extent != std::dynamic_extent;

// clang-format on

/**
 * Find the length in bytes of a given contiguous range @p r.
 */
inline constexpr size_t size_bytes(const spanable_range auto& r) {
   return std::span{r}.size_bytes();
}

/**
* Throws an exception indicating that the attempted read or write was invalid
*/
[[noreturn]] void BOTAN_UNSTABLE_API memory_region_size_violation();

/**
 * Check that a given range @p r has a certain statically-known byte length. If
 * the range's extent is known at compile time, this is a static check,
 * otherwise a runtime argument check will be added.
 *
 * @throws Invalid_Argument  if range @p r has a dynamic extent and does not
 *                           feature the expected byte length.
 */
template <size_t expected, spanable_range R>
inline constexpr void assert_exact_byte_length(const R& r) {
   const std::span s{r};
   if constexpr(statically_spanable_range<R>) {
      static_assert(s.size_bytes() == expected, "memory region does not have expected byte lengths");
   } else {
      if(s.size_bytes() != expected) {
         memory_region_size_violation();
      }
   }
}

/**
 * Check that a list of ranges (in @p r0 and @p rs) all have the same byte
 * lengths. If the first range's extent is known at compile time, this will be a
 * static check for all other ranges whose extents are known at compile time,
 * otherwise a runtime argument check will be added.
 *
 * @throws Invalid_Argument  if any range has a dynamic extent and not all
 *                           ranges feature the same byte length.
 */
template <spanable_range R0, spanable_range... Rs>
inline constexpr void assert_equal_byte_lengths(const R0& r0, const Rs&... rs)
   requires(sizeof...(Rs) > 0)
{
   const std::span s0{r0};

   if constexpr(statically_spanable_range<R0>) {
      constexpr size_t expected_size = s0.size_bytes();
      (assert_exact_byte_length<expected_size>(rs), ...);
   } else {
      const size_t expected_size = s0.size_bytes();
      const bool correct_size =
         ((std::span<const std::ranges::range_value_t<Rs>>{rs}.size_bytes() == expected_size) && ...);

      if(!correct_size) {
         memory_region_size_violation();
      }
   }
}

}  // namespace Botan::ranges

BOTAN_FUTURE_INTERNAL_HEADER(mem_ops.h)

/*
The header mem_ops.h previously included the contents of allocator.h

Library code should always include allocator.h to see these
declarations; however when we are not building the library continue to
include the header here to avoid breaking application code.
*/
#if !defined(BOTAN_IS_BEING_BUILT)
#endif

namespace Botan {

/**
* Scrub memory contents in a way that a compiler should not elide,
* using some system specific technique. Note that this function might
* not zero the memory (for example, in some hypothetical
* implementation it might combine the memory contents with the output
* of a system PRNG), but if you can detect any difference in behavior
* at runtime then the clearing is side-effecting and you can just
* use `clear_mem`.
*
* Use this function to scrub memory just before deallocating it, or on
* a stack buffer before returning from the function.
*
* @param ptr a pointer to memory to scrub
* @param n the number of bytes pointed to by ptr
*/
BOTAN_PUBLIC_API(2, 0) void secure_scrub_memory(void* ptr, size_t n);

/**
* Zero memory contents in a way that a compiler should not elide,
* using some system specific technique.
*
* @param data  the data region to be scrubbed
*/
void secure_scrub_memory(ranges::contiguous_output_range auto&& data) {
   secure_scrub_memory(std::ranges::data(data), ranges::size_bytes(data));
}

/**
* Memory comparison, input insensitive
* @param x a pointer to an array
* @param y a pointer to another array
* @param len the number of Ts in x and y
* @return 0xFF iff x[i] == y[i] forall i in [0...n) or 0x00 otherwise
*/
BOTAN_DEPRECATED("This function is deprecated, use constant_time_compare()")
BOTAN_PUBLIC_API(2, 9) uint8_t ct_compare_u8(const uint8_t x[], const uint8_t y[], size_t len);

/**
 * Memory comparison, input insensitive
 * @param x a range of bytes
 * @param y another range of bytes
 * @return true iff x and y have equal lengths and x[i] == y[i] forall i in [0...n)
 */
BOTAN_PUBLIC_API(3, 3) bool constant_time_compare(std::span<const uint8_t> x, std::span<const uint8_t> y);

/**
* Memory comparison, input insensitive
* @param x a pointer to an array
* @param y a pointer to another array
* @param len the number of Ts in x and y
* @return true iff x[i] == y[i] forall i in [0...n)
*/
inline bool constant_time_compare(const uint8_t x[], const uint8_t y[], size_t len) {
   // simply assumes that *x and *y point to len allocated bytes at least
   return constant_time_compare({x, len}, {y, len});
}

/**
* Zero out some bytes. Warning: use secure_scrub_memory instead if the
* memory is about to be freed or otherwise the compiler thinks it can
* elide the writes.
*
* @param ptr a pointer to memory to zero
* @param bytes the number of bytes to zero in ptr
*/
inline constexpr void clear_bytes(void* ptr, size_t bytes) {
   if(bytes > 0) {
      std::memset(ptr, 0, bytes);
   }
}

/**
* Zero memory before use. This simply calls memset and should not be
* used in cases where the compiler cannot see the call as a
* side-effecting operation (for example, if calling clear_mem before
* deallocating memory, the compiler would be allowed to omit the call
* to memset entirely under the as-if rule.)
*
* @param ptr a pointer to an array of Ts to zero
* @param n the number of Ts pointed to by ptr
*/
template <typename T>
inline constexpr void clear_mem(T* ptr, size_t n) {
   clear_bytes(ptr, sizeof(T) * n);
}

/**
* Zero memory before use. This simply calls memset and should not be
* used in cases where the compiler cannot see the call as a
* side-effecting operation.
*
* @param mem a contiguous range of Ts to zero
*/
template <ranges::contiguous_output_range R>
inline constexpr void clear_mem(R&& mem)  // NOLINT(*-missing-std-forward)
   requires std::is_trivially_copyable_v<std::ranges::range_value_t<R>>
{
   clear_bytes(std::ranges::data(mem), ranges::size_bytes(mem));
}

/**
* Copy memory
* @param out the destination array
* @param in the source array
* @param n the number of elements of in/out
*/
template <typename T>
   requires std::is_trivial_v<std::decay_t<T>>
inline constexpr void copy_mem(T* out, const T* in, size_t n) {
   BOTAN_ASSERT_IMPLICATION(n > 0, in != nullptr && out != nullptr, "If n > 0 then args are not null");

   if(in != nullptr && out != nullptr && n > 0) {
      std::memmove(out, in, sizeof(T) * n);
   }
}

/**
* Copy memory
* @param out the destination array
* @param in the source array
*/
template <ranges::contiguous_output_range OutR, ranges::contiguous_range InR>
   requires std::is_same_v<std::ranges::range_value_t<OutR>, std::ranges::range_value_t<InR>> &&
            std::is_trivially_copyable_v<std::ranges::range_value_t<InR>>
inline constexpr void copy_mem(OutR&& out /* NOLINT(*-std-forward) */, const InR& in) {
   ranges::assert_equal_byte_lengths(out, in);
   if(std::is_constant_evaluated()) {
      std::copy(std::ranges::begin(in), std::ranges::end(in), std::ranges::begin(out));
   } else if(ranges::size_bytes(out) > 0) {
      std::memmove(std::ranges::data(out), std::ranges::data(in), ranges::size_bytes(out));
   }
}

/**
 * Copy a range of a trivially copyable type into another range of trivially
 * copyable type of matching byte length.
 */
template <ranges::contiguous_output_range ToR, ranges::contiguous_range FromR>
   requires std::is_trivially_copyable_v<std::ranges::range_value_t<FromR>> &&
            std::is_trivially_copyable_v<std::ranges::range_value_t<ToR>>
inline constexpr void typecast_copy(ToR&& out /* NOLINT(*-std-forward) */, const FromR& in) {
   ranges::assert_equal_byte_lengths(out, in);
   std::memcpy(std::ranges::data(out), std::ranges::data(in), ranges::size_bytes(out));
}

/**
 * Copy a range of trivially copyable type into an instance of trivially
 * copyable type with matching length.
 */
template <typename ToT, ranges::contiguous_range FromR>
   requires std::is_trivially_copyable_v<std::ranges::range_value_t<FromR>> && std::is_trivially_copyable_v<ToT> &&
            (!std::ranges::range<ToT>)
inline constexpr void typecast_copy(ToT& out, const FromR& in) {
   typecast_copy(std::span<ToT, 1>(&out, 1), in);
}

/**
 * Copy an instance of trivially copyable type into a range of trivially
 * copyable type with matching length.
 */
template <ranges::contiguous_output_range ToR, typename FromT>
   requires std::is_trivially_copyable_v<FromT> &&
            (!std::ranges::range<FromT>) && std::is_trivially_copyable_v<std::ranges::range_value_t<ToR>>
inline constexpr void typecast_copy(ToR&& out /* NOLINT(*-std-forward) */, const FromT& in) {
   typecast_copy(out, std::span<const FromT, 1>(&in, 1));
}

/**
 * Create a trivial type by bit-casting a range of trivially copyable type with
 * matching length into it.
 */
template <typename ToT, ranges::contiguous_range FromR>
   requires std::is_default_constructible_v<ToT> && std::is_trivially_copyable_v<ToT> &&
            std::is_trivially_copyable_v<std::ranges::range_value_t<FromR>>
inline constexpr ToT typecast_copy(const FromR& src) {
   ToT dst;  // NOLINT(*-member-init)
   typecast_copy(dst, src);
   return dst;
}

/**
* Copy the bytes of an array of trivially copyable objects into a byte array
* @param out the output byte array, must have room for sizeof(T)*N bytes
* @param in the input array
* @param N the number of elements in the input array
*/
// TODO: deprecate and replace
template <typename T>
inline constexpr void typecast_copy(uint8_t out[], T in[], size_t N)
   requires std::is_trivially_copyable_v<T>
{
   // asserts that *in and *out point to the correct amount of memory
   typecast_copy(std::span<uint8_t>(out, sizeof(T) * N), std::span<const T>(in, N));
}

/**
* Reinterpret a byte array as an array of trivial objects
* @param out the output array, must have room for N elements
* @param in the input byte array, must hold sizeof(T)*N bytes
* @param N the number of elements to produce
*/
// TODO: deprecate and replace
template <typename T>
inline constexpr void typecast_copy(T out[], const uint8_t in[], size_t N)
   requires std::is_trivial_v<T>
{
   // asserts that *in and *out point to the correct amount of memory
   typecast_copy(std::span<T>(out, N), std::span<const uint8_t>(in, N * sizeof(T)));
}

/**
* Copy the bytes of a single object into a byte array
* @param out the output byte array, must have room for sizeof(T) bytes
* @param in the object to copy from
*/
// TODO: deprecate and replace
template <typename T>
inline constexpr void typecast_copy(uint8_t out[], const T& in) {
   // asserts that *out points to the correct amount of memory
   typecast_copy(std::span<uint8_t, sizeof(T)>(out, sizeof(T)), in);
}

/**
* Reinterpret a byte array as a single trivial object
* @param out the object to copy into
* @param in the input byte array, must hold sizeof(T) bytes
*/
// TODO: deprecate and replace
template <typename T>
   requires std::is_trivial_v<std::decay_t<T>>
inline constexpr void typecast_copy(T& out, const uint8_t in[]) {
   // asserts that *in points to the correct amount of memory
   typecast_copy(out, std::span<const uint8_t, sizeof(T)>(in, sizeof(T)));
}

/**
* Reinterpret a byte array as a single trivial object
* @param src the input byte array, must hold sizeof(To) bytes
* @return the object read from src
*/
// TODO: deprecate and replace
template <typename To>
   requires std::is_trivial_v<To>
inline constexpr To typecast_copy(const uint8_t src[]) noexcept {
   // asserts that *src points to the correct amount of memory
   return typecast_copy<To>(std::span<const uint8_t, sizeof(To)>(src, sizeof(To)));
}

#if !defined(BOTAN_IS_BEING_BUILT)
/**
* Set memory to a fixed value
* @param ptr a pointer to an array of bytes
* @param n the number of Ts pointed to by ptr
* @param val the value to set each byte to
*/
BOTAN_DEPRECATED("This function is deprecated") inline constexpr void set_mem(uint8_t* ptr, size_t n, uint8_t val) {
   if(n > 0) {
      std::memset(ptr, val, n);
   }
}
#endif

#if !defined(BOTAN_IS_BEING_BUILT)
/**
* Cast a char pointer to a uint8_t pointer
* @param s the pointer to cast
* @return s viewed as a byte pointer
*/
inline const uint8_t* cast_char_ptr_to_uint8(const char* s) {
   return reinterpret_cast<const uint8_t*>(s);
}

/**
* Cast a char pointer to a uint8_t pointer
* @param s the pointer to cast
* @return s viewed as a byte pointer
*/
inline uint8_t* cast_char_ptr_to_uint8(char* s) {
   return reinterpret_cast<uint8_t*>(s);
}
#endif

/**
* Cast a uint8_t pointer to a char pointer
* @param b the pointer to cast
* @return b viewed as a char pointer
*/
inline const char* cast_uint8_ptr_to_char(const uint8_t* b) {
   return reinterpret_cast<const char*>(b);
}

/**
* Cast a uint8_t pointer to a char pointer
* @param b the pointer to cast
* @return b viewed as a char pointer
*/
inline char* cast_uint8_ptr_to_char(uint8_t* b) {
   return reinterpret_cast<char*>(b);
}

#if !defined(BOTAN_IS_BEING_BUILT)
/**
* Memory comparison, input insensitive
* @param p1 a pointer to an array
* @param p2 a pointer to another array
* @param n the number of Ts in p1 and p2
* @return true iff p1[i] == p2[i] forall i in [0...n)
*/
template <typename T>
BOTAN_DEPRECATED("This function is deprecated")
inline bool same_mem(const T* p1, const T* p2, size_t n) {
   volatile T difference = 0;

   for(size_t i = 0; i != n; ++i) {
      difference = difference | (p1[i] ^ p2[i]);
   }

   return difference == 0;
}
#endif

#if !defined(BOTAN_IS_BEING_BUILT)

/**
* Copy into a buffer at an offset, truncating to the space available
* @param buf the buffer to write into
* @param buf_offset the offset in buf to write at
* @param input the elements to copy
* @param input_length the number of elements in input
* @return the number of elements actually copied
*/
template <typename T, typename Alloc>
BOTAN_DEPRECATED("The buffer_insert functions are deprecated")
size_t buffer_insert(std::vector<T, Alloc>& buf, size_t buf_offset, const T input[], size_t input_length) {
   BOTAN_ASSERT_NOMSG(buf_offset <= buf.size());
   const size_t to_copy = std::min(input_length, buf.size() - buf_offset);
   if(to_copy > 0) {
      copy_mem(&buf[buf_offset], input, to_copy);
   }
   return to_copy;
}

/**
* Copy into a buffer at an offset, truncating to the space available
* @param buf the buffer to write into
* @param buf_offset the offset in buf to write at
* @param input the elements to copy
* @return the number of elements actually copied
*/
template <typename T, typename Alloc, typename Alloc2>
BOTAN_DEPRECATED("The buffer_insert functions are deprecated")
size_t buffer_insert(std::vector<T, Alloc>& buf, size_t buf_offset, const std::vector<T, Alloc2>& input) {
   BOTAN_ASSERT_NOMSG(buf_offset <= buf.size());
   const size_t to_copy = std::min(input.size(), buf.size() - buf_offset);
   if(to_copy > 0) {
      copy_mem(&buf[buf_offset], input.data(), to_copy);
   }
   return to_copy;
}

#endif

/**
* XOR arrays. Postcondition out[i] = in[i] ^ out[i] forall i = 0...length
* @param out the input/output range
* @param in the read-only input range
*/
inline constexpr void xor_buf(ranges::contiguous_output_range<uint8_t> auto&& out,
                              ranges::contiguous_range<uint8_t> auto&& in) {
   ranges::assert_equal_byte_lengths(out, in);

   std::span<uint8_t> o(out);
   std::span<const uint8_t> i(in);

   for(; o.size_bytes() >= 32; o = o.subspan(32), i = i.subspan(32)) {
      auto x = typecast_copy<std::array<uint64_t, 4>>(o.template first<32>());
      const auto y = typecast_copy<std::array<uint64_t, 4>>(i.template first<32>());

      x[0] ^= y[0];
      x[1] ^= y[1];
      x[2] ^= y[2];
      x[3] ^= y[3];

      typecast_copy(o.template first<32>(), x);
   }

   for(size_t off = 0; off != o.size_bytes(); ++off) {
      o[off] ^= i[off];
   }
}

/**
* XOR arrays. Postcondition out[i] = in1[i] ^ in2[i] forall i = 0...length
* @param out the output range
* @param in1 the first input range
* @param in2 the second input range
*/
inline constexpr void xor_buf(ranges::contiguous_output_range<uint8_t> auto&& out,
                              ranges::contiguous_range<uint8_t> auto&& in1,
                              ranges::contiguous_range<uint8_t> auto&& in2) {
   ranges::assert_equal_byte_lengths(out, in1, in2);

   std::span o{out};
   std::span i1{in1};
   std::span i2{in2};

   for(; o.size_bytes() >= 32; o = o.subspan(32), i1 = i1.subspan(32), i2 = i2.subspan(32)) {
      auto x = typecast_copy<std::array<uint64_t, 4>>(i1.template first<32>());
      const auto y = typecast_copy<std::array<uint64_t, 4>>(i2.template first<32>());

      x[0] ^= y[0];
      x[1] ^= y[1];
      x[2] ^= y[2];
      x[3] ^= y[3];

      typecast_copy(o.template first<32>(), x);
   }

   for(size_t off = 0; off != o.size_bytes(); ++off) {
      o[off] = i1[off] ^ i2[off];
   }
}

/**
* XOR arrays. Postcondition out[i] = in[i] ^ out[i] forall i = 0...length
* @param out the input/output buffer
* @param in the read-only input buffer
* @param length the length of the buffers
*/
inline void xor_buf(uint8_t out[], const uint8_t in[], size_t length) {
   // simply assumes that *out and *in point to "length" allocated bytes at least
   xor_buf(std::span{out, length}, std::span{in, length});
}

/**
* XOR arrays. Postcondition out[i] = in[i] ^ in2[i] forall i = 0...length
* @param out the output buffer
* @param in the first input buffer
* @param in2 the second input buffer
* @param length the length of the three buffers
*/
inline void xor_buf(uint8_t out[], const uint8_t in[], const uint8_t in2[], size_t length) {
   // simply assumes that *out, *in, and *in2 point to "length" allocated bytes at least
   xor_buf(std::span{out, length}, std::span{in, length}, std::span{in2, length});
}

/**
* XOR the first n bytes of in into out
* @param out the buffer to XOR into, must hold at least n bytes
* @param in the buffer to read from, must hold at least n bytes
* @param n the number of bytes to XOR
*/
// TODO: deprecate and replace, use .subspan()
inline void xor_buf(std::span<uint8_t> out, std::span<const uint8_t> in, size_t n) {
   BOTAN_ARG_CHECK(out.size() >= n, "output span is too small");
   BOTAN_ARG_CHECK(in.size() >= n, "input span is too small");
   xor_buf(out.first(n), in.first(n));
}

/**
* XOR n bytes into the front of a vector
* @param out the vector to XOR into, must hold at least n bytes
* @param in the bytes to read from, must point to at least n bytes
* @param n the number of bytes to XOR
*/
// TODO: deprecate and replace, use .subspan()
template <typename Alloc>
void xor_buf(std::vector<uint8_t, Alloc>& out, const uint8_t* in, size_t n) {
   BOTAN_ARG_CHECK(out.size() >= n, "output vector is too small");
   // simply assumes that *in points to "n" allocated bytes at least
   xor_buf(std::span{out}.first(n), std::span{in, n});
}

/**
* Set the front of a vector to the XOR of two inputs
* @param out the vector to write into, must hold at least n bytes
* @param in the first input, must point to at least n bytes
* @param in2 the second input, must hold at least n bytes
* @param n the number of bytes to process
*/
// TODO: deprecate and replace
template <typename Alloc, typename Alloc2>
void xor_buf(std::vector<uint8_t, Alloc>& out, const uint8_t* in, const std::vector<uint8_t, Alloc2>& in2, size_t n) {
   BOTAN_ARG_CHECK(out.size() >= n, "output vector is too small");
   BOTAN_ARG_CHECK(in2.size() >= n, "input vector is too small");
   // simply assumes that *in points to "n" allocated bytes at least
   xor_buf(std::span{out}.first(n), std::span{in, n}, std::span{in2}.first(n));
}

/**
* XOR a vector into another, growing the destination if it is shorter
* @param out the vector to XOR into
* @param in the vector to read from
* @return reference to out
*/
template <typename Alloc, typename Alloc2>
std::vector<uint8_t, Alloc>& operator^=(std::vector<uint8_t, Alloc>& out, const std::vector<uint8_t, Alloc2>& in) {
   if(out.size() < in.size()) {
      out.resize(in.size());
   }

   xor_buf(std::span{out}.first(in.size()), in);
   return out;
}

}  // namespace Botan

namespace Botan {

class BlockCipher;

/**
* Key wrap. See RFC 3394 and NIST SP800-38F
* @param input the value to be encrypted
* @param input_len length of input, must be a multiple of 8
* @param bc a keyed 128-bit block cipher that will be used to encrypt input
* @return input encrypted under NIST key wrap algorithm
*/
std::vector<uint8_t> BOTAN_PUBLIC_API(2, 4)
   nist_key_wrap(const uint8_t input[], size_t input_len, const BlockCipher& bc);

/**
* Key wrap. See RFC 3394 and NIST SP800-38F
* @param input the value to be encrypted
* @param bc a keyed 128-bit block cipher that will be used to encrypt input
* @return input encrypted under NIST key wrap algorithm
*/
inline std::vector<uint8_t> nist_key_wrap(std::span<const uint8_t> input, const BlockCipher& bc) {
   return nist_key_wrap(input.data(), input.size(), bc);
}

/**
* KW (key unwrap). See RFC 3394 and NIST SP800-38F
* @param input the value to be decrypted, output of nist_key_wrap
* @param input_len length of input
* @param bc a keyed 128-bit block cipher that will be used to decrypt input
* @return input decrypted under NIST key wrap algorithm
* Throws an exception if decryption fails.
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 4)
   nist_key_unwrap(const uint8_t input[], size_t input_len, const BlockCipher& bc);

/**
* KW (key unwrap). See RFC 3394 and NIST SP800-38F
* @param input the value to be decrypted, output of nist_key_wrap
* @param bc a keyed 128-bit block cipher that will be used to decrypt input
* @return input decrypted under NIST key wrap algorithm
* Throws an exception if decryption fails.
*/
inline secure_vector<uint8_t> nist_key_unwrap(std::span<const uint8_t> input, const BlockCipher& bc) {
   return nist_key_unwrap(input.data(), input.size(), bc);
}

/**
* KWP (key wrap with padding). See RFC 5649 and NIST SP800-38F
* @param input the value to be encrypted
* @param input_len length of input
* @param bc a keyed 128-bit block cipher that will be used to encrypt input
* @return input encrypted under NIST key wrap algorithm
*/
std::vector<uint8_t> BOTAN_PUBLIC_API(2, 4)
   nist_key_wrap_padded(const uint8_t input[], size_t input_len, const BlockCipher& bc);

/**
* KWP (key wrap with padding). See RFC 5649 and NIST SP800-38F
* @param input the value to be encrypted
* @param bc a keyed 128-bit block cipher that will be used to encrypt input
* @return input encrypted under NIST key wrap algorithm
*/
inline std::vector<uint8_t> nist_key_wrap_padded(std::span<const uint8_t> input, const BlockCipher& bc) {
   return nist_key_wrap_padded(input.data(), input.size(), bc);
}

/**
* KWP (key unwrap with padding). See RFC 5649 and NIST SP800-38F
* @param input the value to be decrypted, output of nist_key_wrap
* @param input_len length of input
* @param bc a keyed 128-bit block cipher that will be used to decrypt input
* @return input decrypted under NIST key wrap algorithm
* Throws an exception if decryption fails.
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 4)
   nist_key_unwrap_padded(const uint8_t input[], size_t input_len, const BlockCipher& bc);

/**
* KWP (key unwrap with padding). See RFC 5649 and NIST SP800-38F
* @param input the value to be decrypted, output of nist_key_wrap
* @param bc a keyed 128-bit block cipher that will be used to decrypt input
* @return input decrypted under NIST key wrap algorithm
* Throws an exception if decryption fails.
*/
inline secure_vector<uint8_t> nist_key_unwrap_padded(std::span<const uint8_t> input, const BlockCipher& bc) {
   return nist_key_unwrap_padded(input.data(), input.size(), bc);
}

}  // namespace Botan

namespace Botan {

class RandomNumberGenerator;

/**
* Octet String
*/
class BOTAN_PUBLIC_API(2, 0) OctetString final {
   public:
      /**
      * Return the length of this octet string
      * @return size of this octet string in bytes
      */
      size_t length() const { return m_data.size(); }

      /**
      * Return the length of this octet string
      * @return size of this octet string in bytes
      */
      size_t size() const { return m_data.size(); }

      /**
      * Test whether this octet string is empty
      * @return true if this string holds no bytes
      */
      bool empty() const { return m_data.empty(); }

      /**
      * Return the contents of this octet string
      * @return this object as a secure_vector<uint8_t>
      */
      secure_vector<uint8_t> bits_of() const { return m_data; }

      /**
      * Return a pointer to the first byte
      * @return start of this string
      */
      const uint8_t* begin() const { return m_data.data(); }

      /**
      * Return a pointer one past the last byte
      * @return end of this string
      */
      const uint8_t* end() const { return begin() + m_data.size(); }

      /**
      * Format this octet string as a hex string
      * @return this encoded as hex
      */
      std::string to_string() const;

      /**
      * XOR the contents of another octet string into this one
      * @param other octet string
      * @return reference to this
      */
      OctetString& operator^=(const OctetString& other);

      /**
      * Force to have odd parity
      *
      * Deprecated. There is no reason to use this outside of interacting with
      * some very old or weird system which requires DES and also which do not
      * automatically ignore the parity bits.
      */
      BOTAN_DEPRECATED("Why would you need to do this") void set_odd_parity();

      /**
      * Create a new OctetString
      * @param str is a hex encoded string
      */
      explicit OctetString(std::string_view str = "");

      /**
      * Create a new random OctetString
      * @param rng is a random number generator
      * @param len is the desired length in bytes
      */
      OctetString(RandomNumberGenerator& rng, size_t len);

      /**
      * Create a new OctetString
      * @param in is an array
      * @param len is the length of in in bytes
      */
      OctetString(const uint8_t in[], size_t len);

      /**
      * Create a new OctetString
      * @param in a bytestring
      */
      explicit OctetString(std::span<const uint8_t> in) : m_data(in.begin(), in.end()) {}

      /**
      * Create a new OctetString
      * @param in a bytestring
      */
      explicit OctetString(secure_vector<uint8_t> in) : m_data(std::move(in)) {}

   private:
      secure_vector<uint8_t> m_data;
};

/**
* Compare two strings
* @param x an octet string
* @param y an octet string
* @return if x is equal to y
*/
BOTAN_PUBLIC_API(2, 0) bool operator==(const OctetString& x, const OctetString& y);

/**
* Compare two strings
* @param x an octet string
* @param y an octet string
* @return if x is not equal to y
*/
BOTAN_PUBLIC_API(2, 0) bool operator!=(const OctetString& x, const OctetString& y);

/**
* Concatenate two strings
* @param x an octet string
* @param y an octet string
* @return x concatenated with y
*/
BOTAN_PUBLIC_API(2, 0) OctetString operator+(const OctetString& x, const OctetString& y);

/**
* XOR two strings
* @param x an octet string
* @param y an octet string
* @return x XORed with y
*/
BOTAN_PUBLIC_API(2, 0) OctetString operator^(const OctetString& x, const OctetString& y);

/**
* Alternate name for octet string showing intent to use as a key
*/
using SymmetricKey = OctetString;

/**
* Alternate name for octet string showing intent to use as an IV
*/
using InitializationVector = OctetString;

}  // namespace Botan

/*
* This entire interface is deprecated. Use the interface in pwdhash.h
*/
BOTAN_DEPRECATED_HEADER("pbkdf.h")

namespace Botan {

/**
* Base class for PBKDF (password based key derivation function)
* implementations. Converts a password into a key using a salt
* and iterated hashing to make brute force attacks harder.
*
* Starting in 2.8 this functionality is also offered by PasswordHash.
*
* @warning
* This class will be removed in a future major release. Use PasswordHash
*/
class BOTAN_PUBLIC_API(2, 0) PBKDF /* NOLINT(*-special-member-functions) */ {
   public:
      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to choose
      * @return a null pointer if the algo/provider combination cannot be found
      */
      BOTAN_DEPRECATED("Use PasswordHashFamily + PasswordHash")
      static std::unique_ptr<PBKDF> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name, or throw if the
      * algo/provider combination cannot be found. If provider is
      * empty then best available is chosen.
      */
      BOTAN_DEPRECATED("Use PasswordHashFamily + PasswordHash")
      static std::unique_ptr<PBKDF> create_or_throw(std::string_view algo_spec, std::string_view provider = "");

      /**
      * List the providers available for a given PBKDF
      * @return list of available providers for this algorithm, empty if not available
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Create a new uninitialized object of the same type
      * @return new instance of this same algorithm
      */
      virtual std::unique_ptr<PBKDF> new_object() const = 0;

      /**
      * Create a new uninitialized object of the same type
      * @return new instance of this same algorithm
      */
      PBKDF* clone() const { return this->new_object().release(); }

      /**
      * Return free-form string identifying this algorithm
      */
      virtual std::string name() const = 0;

      virtual ~PBKDF() = default;

      /**
      * Derive a key from a passphrase for a number of iterations
      * specified by either iterations or if iterations == 0 then
      * running until msec time has elapsed.
      *
      * @param out buffer to store the derived key, must be of out_len bytes
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param iterations the number of iterations to use (use 10K or more)
      * @param msec if iterations is zero, then instead the PBKDF is
      *        run until msec milliseconds has passed.
      * @return the number of iterations performed
      */
      virtual size_t pbkdf(uint8_t out[],
                           size_t out_len,
                           std::string_view passphrase,
                           const uint8_t salt[],
                           size_t salt_len,
                           size_t iterations,
                           std::chrono::milliseconds msec) const = 0;

      /**
      * Derive a key from a passphrase for a number of iterations.
      *
      * @param out buffer to store the derived key, must be of out_len bytes
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param iterations the number of iterations to use (use 10K or more)
      */
      void pbkdf_iterations(uint8_t out[],
                            size_t out_len,
                            std::string_view passphrase,
                            const uint8_t salt[],
                            size_t salt_len,
                            size_t iterations) const;

      /**
      * Derive a key from a passphrase, running until msec time has elapsed.
      *
      * @param out buffer to store the derived key, must be of out_len bytes
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param msec if iterations is zero, then instead the PBKDF is
      *        run until msec milliseconds has passed.
      * @param iterations set to the number iterations executed
      */
      void pbkdf_timed(uint8_t out[],
                       size_t out_len,
                       std::string_view passphrase,
                       const uint8_t salt[],
                       size_t salt_len,
                       std::chrono::milliseconds msec,
                       size_t& iterations) const;

      /**
      * Derive a key from a passphrase for a number of iterations.
      *
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param iterations the number of iterations to use (use 10K or more)
      * @return the derived key
      */
      secure_vector<uint8_t> pbkdf_iterations(
         size_t out_len, std::string_view passphrase, const uint8_t salt[], size_t salt_len, size_t iterations) const;

      /**
      * Derive a key from a passphrase, running until msec time has elapsed.
      *
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param msec if iterations is zero, then instead the PBKDF is
      *        run until msec milliseconds has passed.
      * @param iterations set to the number iterations executed
      * @return the derived key
      */
      secure_vector<uint8_t> pbkdf_timed(size_t out_len,
                                         std::string_view passphrase,
                                         const uint8_t salt[],
                                         size_t salt_len,
                                         std::chrono::milliseconds msec,
                                         size_t& iterations) const;

      // Following kept for compat with 1.10:

      /**
      * Derive a key from a passphrase
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param iterations the number of iterations to use (use 10K or more)
      */
      OctetString derive_key(
         size_t out_len, std::string_view passphrase, const uint8_t salt[], size_t salt_len, size_t iterations) const {
         return OctetString(pbkdf_iterations(out_len, passphrase, salt, salt_len, iterations));
      }

      /**
      * Derive a key from a passphrase
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param iterations the number of iterations to use (use 10K or more)
      */
      template <typename Alloc>
      OctetString derive_key(size_t out_len,
                             std::string_view passphrase,
                             const std::vector<uint8_t, Alloc>& salt,
                             size_t iterations) const {
         return OctetString(pbkdf_iterations(out_len, passphrase, salt.data(), salt.size(), iterations));
      }

      /**
      * Derive a key from a passphrase
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param salt_len length of salt in bytes
      * @param msec is how long to run the PBKDF
      * @param iterations is set to the number of iterations used
      */
      OctetString derive_key(size_t out_len,
                             std::string_view passphrase,
                             const uint8_t salt[],
                             size_t salt_len,
                             std::chrono::milliseconds msec,
                             size_t& iterations) const {
         return OctetString(pbkdf_timed(out_len, passphrase, salt, salt_len, msec, iterations));
      }

      /**
      * Derive a key from a passphrase using a certain amount of time
      * @param out_len the desired length of the key to produce
      * @param passphrase the password to derive the key from
      * @param salt a randomly chosen salt
      * @param msec is how long to run the PBKDF
      * @param iterations is set to the number of iterations used
      */
      template <typename Alloc>
      OctetString derive_key(size_t out_len,
                             std::string_view passphrase,
                             const std::vector<uint8_t, Alloc>& salt,
                             std::chrono::milliseconds msec,
                             size_t& iterations) const {
         return OctetString(pbkdf_timed(out_len, passphrase, salt.data(), salt.size(), msec, iterations));
      }
};

/**
* Compatibility typedef for PBKDF
*/
typedef PBKDF S2K;

/**
* Password based key derivation function factory method
* @param algo_spec the name of the desired PBKDF algorithm
* @param provider the provider to use
* @return pointer to newly allocated object of that type
*/
BOTAN_DEPRECATED("Use PasswordHashFamily + PasswordHash")
inline PBKDF* get_pbkdf(std::string_view algo_spec, std::string_view provider = "") {
   return PBKDF::create_or_throw(algo_spec, provider).release();
}

/**
* Password based key derivation function factory method
* @param algo_spec the name of the desired PBKDF algorithm
* @return pointer to newly allocated object of that type
*/
BOTAN_DEPRECATED("Use PasswordHashFamily + PasswordHash") inline PBKDF* get_s2k(std::string_view algo_spec) {
   return PBKDF::create_or_throw(algo_spec).release();
}

}  // namespace Botan

// Use pwdhash.h
BOTAN_FUTURE_INTERNAL_HEADER(pbkdf2.h)

namespace Botan {

BOTAN_PUBLIC_API(2, 0)
size_t pbkdf2(MessageAuthenticationCode& prf,
              uint8_t out[],
              size_t out_len,
              std::string_view passphrase,
              const uint8_t salt[],
              size_t salt_len,
              size_t iterations,
              std::chrono::milliseconds msec);

/**
* Perform PBKDF2. The prf is assumed to be keyed already.
*/
BOTAN_PUBLIC_API(2, 8)
void pbkdf2(MessageAuthenticationCode& prf,
            uint8_t out[],
            size_t out_len,
            const uint8_t salt[],
            size_t salt_len,
            size_t iterations);

/**
* PBKDF2
*/
class BOTAN_PUBLIC_API(2, 8) PBKDF2 final : public PasswordHash {
   public:
      PBKDF2(const MessageAuthenticationCode& prf, size_t iter) : m_prf(prf.new_object()), m_iterations(iter) {}

      BOTAN_DEPRECATED("For runtime tuning use PBKDF2_Family::tune_params")
      PBKDF2(const MessageAuthenticationCode& prf, size_t olen, std::chrono::milliseconds msec);

      size_t iterations() const override { return m_iterations; }

      std::string to_string() const override;

      void derive_key(uint8_t out[],
                      size_t out_len,
                      const char* password,
                      size_t password_len,
                      const uint8_t salt[],
                      size_t salt_len) const override;

   private:
      std::unique_ptr<MessageAuthenticationCode> m_prf;
      size_t m_iterations;
};

/**
* Family of PKCS #5 PBKDF2 operations
*/
class BOTAN_PUBLIC_API(2, 8) PBKDF2_Family final : public PasswordHashFamily {
   public:
      BOTAN_FUTURE_EXPLICIT PBKDF2_Family(std::unique_ptr<MessageAuthenticationCode> prf) : m_prf(std::move(prf)) {}

      std::string name() const override;

      std::unique_ptr<PasswordHash> tune_params(size_t output_len,
                                                uint64_t desired_runtime_msec,
                                                std::optional<size_t> max_memory,
                                                uint64_t tune_msec) const override;

      /**
      * Return some default parameter set for this PBKDF that should be good
      * enough for most users. The value returned may change over time as
      * processing power and attacks improve.
      */
      std::unique_ptr<PasswordHash> default_params() const override;

      std::unique_ptr<PasswordHash> from_iterations(size_t iter) const override;

      std::unique_ptr<PasswordHash> from_params(size_t iter, size_t /*unused*/, size_t /*unused*/) const override;

   private:
      std::unique_ptr<MessageAuthenticationCode> m_prf;
};

/**
* PKCS #5 PBKDF2 (old interface)
*/
class BOTAN_PUBLIC_API(2, 0) PKCS5_PBKDF2 final : public PBKDF {
   public:
      std::string name() const override;

      std::unique_ptr<PBKDF> new_object() const override;

      size_t pbkdf(uint8_t output_buf[],
                   size_t output_len,
                   std::string_view passphrase,
                   const uint8_t salt[],
                   size_t salt_len,
                   size_t iterations,
                   std::chrono::milliseconds msec) const override;

      /**
      * Create a PKCS #5 instance using the specified message auth code
      * @param mac_fn the MAC object to use as PRF
      */
      BOTAN_DEPRECATED("Use version taking unique_ptr")
      explicit PKCS5_PBKDF2(MessageAuthenticationCode* mac_fn) : m_mac(mac_fn) {}

      /**
      * Create a PKCS #5 instance using the specified message auth code
      * @param mac_fn the MAC object to use as PRF
      */
      BOTAN_DEPRECATED("Use PasswordHashFamily + PasswordHash")
      explicit PKCS5_PBKDF2(std::unique_ptr<MessageAuthenticationCode> mac_fn) : m_mac(std::move(mac_fn)) {}

   private:
      std::unique_ptr<MessageAuthenticationCode> m_mac;
};

}  // namespace Botan

namespace Botan {

/**
* Encrypt a key under a key encryption key using the algorithm
* described in RFC 3394
*
* @param key the plaintext key to encrypt
* @param kek the key encryption key
* @return key encrypted under kek
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 0)
   rfc3394_keywrap(const secure_vector<uint8_t>& key, const SymmetricKey& kek);

/**
* Decrypt a key under a key encryption key using the algorithm
* described in RFC 3394
*
* @param key the encrypted key to decrypt
* @param kek the key encryption key
* @return key decrypted under kek
*/
secure_vector<uint8_t> BOTAN_PUBLIC_API(2, 0)
   rfc3394_keyunwrap(const secure_vector<uint8_t>& key, const SymmetricKey& kek);

}  // namespace Botan

namespace Botan {

/**
* Base class for all stream ciphers
*/
class BOTAN_PUBLIC_API(2, 0) StreamCipher : public SymmetricAlgorithm {
   public:
      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to use
      * @return a null pointer if the algo/provider combination cannot be found
      */
      static std::unique_ptr<StreamCipher> create(std::string_view algo_spec, std::string_view provider = "");

      /**
      * Create an instance based on a name
      * If provider is empty then best available is chosen.
      * @param algo_spec algorithm name
      * @param provider provider implementation to use
      * Throws a Lookup_Error if the algo/provider combination cannot be found
      */
      static std::unique_ptr<StreamCipher> create_or_throw(std::string_view algo_spec, std::string_view provider = "");

      /**
      * List the providers available for a given stream cipher
      * @return list of available providers for this algorithm, empty if not available
      */
      static std::vector<std::string> providers(std::string_view algo_spec);

      /**
      * Encrypt or decrypt a message
      *
      * Processes all bytes plain/ciphertext from @p in and writes the result to
      * @p out.
      *
      * @param in the plaintext
      * @param out the byte array to hold the output, i.e. the ciphertext
      * @param len the length of both in and out in bytes
      */
      void cipher(const uint8_t in[], uint8_t out[], size_t len) { cipher_bytes(in, out, len); }

      /**
      * Encrypt or decrypt a message
      * @param in the plaintext
      * @param out the byte array to hold the output, i.e. the ciphertext
      *            with at least the same size as @p in
      */
      void cipher(std::span<const uint8_t> in, std::span<uint8_t> out);

      /**
      * Write keystream bytes to a buffer
      *
      * The contents of @p out are ignored/overwritten
      *
      * @param out the byte array to hold the keystream
      * @param len the length of out in bytes
      */
      void write_keystream(uint8_t out[], size_t len) { generate_keystream(out, len); }

      /**
      * Fill a given buffer with keystream bytes
      *
      * The contents of @p out are ignored/overwritten
      *
      * @param out the byte array to hold the keystream
      */
      void write_keystream(std::span<uint8_t> out) { generate_keystream(out.data(), out.size()); }

      /**
      * Get @p bytes from the keystream
      *
      * The bytes are written into a continuous byte buffer of your choosing.
      *
      * @param bytes The number of bytes to be produced
      */
      template <concepts::resizable_byte_buffer T = secure_vector<uint8_t>>
      T keystream_bytes(size_t bytes) {
         T out(bytes);
         write_keystream(out);
         return out;
      }

      /**
      * Encrypt or decrypt a message
      * The message is encrypted/decrypted in place.
      * @param buf the plaintext / ciphertext
      * @param len the length of buf in bytes
      */
      void cipher1(uint8_t buf[], size_t len) { cipher(buf, buf, len); }

      /**
      * Encrypt or decrypt a message
      * The message is encrypted/decrypted in place.
      * @param buf the plaintext / ciphertext
      */
      void cipher1(std::span<uint8_t> buf) { cipher(buf, buf); }

      /**
      * Encrypt a message
      * The message is encrypted/decrypted in place.
      * @param inout the plaintext / ciphertext
      */
      void encipher(std::span<uint8_t> inout) { cipher(inout.data(), inout.data(), inout.size()); }

      /**
      * Encrypt a message
      * The message is encrypted in place.
      * @param inout the plaintext / ciphertext
      */
      void encrypt(std::span<uint8_t> inout) { cipher(inout.data(), inout.data(), inout.size()); }

      /**
      * Decrypt a message in place
      * The message is decrypted in place.
      * @param inout the plaintext / ciphertext
      */
      void decrypt(std::span<uint8_t> inout) { cipher(inout.data(), inout.data(), inout.size()); }

      /**
      * Return the optimium buffer size to use with this cipher
      *
      * Most stream ciphers internally produce blocks of bytes.  This function
      * returns that block size. Aligning buffer sizes to a multiple of this
      * size may improve performance by reducing internal buffering overhead.
      *
      * Note the return value of this function may change for any particular
      * algorithm due to changes in the implementation from release to release,
      * or changes in the runtime environment (such as CPUID indicating
      * availability of an optimized implementation). It is not intrinsic to
      * the algorithm; it is just a suggestion for gaining best performance.
      */
      virtual size_t buffer_size() const = 0;

      /**
      * Resync the cipher using the IV
      *
      * Load @p IV into the stream cipher state. This should happen after the
      * key is set (set_key()) and before any operation (encrypt(), decrypt() or
      * seek()) is called.
      *
      * If the cipher does not support IVs, then a call with an empty IV will be
      * accepted and any other length will cause an Invalid_IV_Length exception.
      *
      * @param iv the initialization vector
      * @param iv_len the length of the IV in bytes
      */
      void set_iv(const uint8_t iv[], size_t iv_len) { set_iv_bytes(iv, iv_len); }

      /**
      * Resync the cipher using the IV
      * @param iv the initialization vector
      * @throws Invalid_IV_Length if an incompatible IV was passed.
      */
      void set_iv(std::span<const uint8_t> iv) { set_iv_bytes(iv.data(), iv.size()); }

      /**
      * Return the default (preferred) nonce length
      *
      * If this function returns zero, then this cipher does not support nonces;
      * in this case any call to set_iv with a (non-empty) value will fail.
      *
      * Default implementation returns 0
      */
      virtual size_t default_iv_length() const;

      /**
      * Test if a nonce length is valid for this cipher
      * @param iv_len the length of the IV in bytes
      * @return if the length is valid for this algorithm
      */
      virtual bool valid_iv_length(size_t iv_len) const { return (iv_len == 0); }

      /**
      * Create a new uninitialized object of the same type
      * @return a new object representing the same algorithm as *this
      */
      StreamCipher* clone() const { return this->new_object().release(); }

      /**
      * Create a new uninitialized object of the same type
      * @return new object representing the same algorithm as *this
      */
      virtual std::unique_ptr<StreamCipher> new_object() const = 0;

      /**
      * Set the offset and the state used later to generate the keystream
      *
      * Sets the state of the stream cipher and keystream according to the
      * passed @p offset, exactly as if @p offset bytes had first been
      * encrypted. The key and (if required) the IV have to be set before this
      * can be called.
      *
      * @note Not all ciphers support seeking; such objects will throw
      *       Not_Implemented in this case. Use supports_seek() to query
      *       in advance.
      *
      * @param offset the offset where we begin to generate the keystream
      */
      virtual void seek(uint64_t offset) = 0;

      /**
      * Test whether this cipher supports seeking within the keystream
      * @return true if this cipher implements seek(); false if seek() will
      *         throw Not_Implemented for any offset.
      */
      virtual bool supports_seek() const = 0;

      /**
      * Many stream ciphers are internally based on encrypting a counter of some
      * kind. If the counter wraps around, keystream bytes would be repeated.
      *
      * This function returns the number of keystream bytes that can still be
      * produced under the current key/nonce settings, if that limit fits in a
      * uint64_t. If there is no specific limit (eg due to being based on
      * permutations rather than a counter), or if the limit is at least 2**64
      * bytes (where consuming the entire keystream is not practically
      * possible), then this function returns nullopt.
      *
      * Note this returns nullopt if no key is set (there are no keystream bytes
      * at all available, in that state) or potentially if the nonce is not set
      * (as in some cases, such as ChaCha, the available counter bytes vary
      * depending on the size of the nonce used).
      */
      virtual std::optional<uint64_t> remaining_keystream_bytes() const = 0;

      /**
      * Return the name of the provider implementing this object
      * @return provider information about this implementation. Default is "base",
      * might also return "sse2", "avx2" or some other arbitrary string.
      */
      virtual std::string provider() const { return "base"; }

   protected:
      /**
      * Encrypt or decrypt a message
      */
      virtual void cipher_bytes(const uint8_t in[], uint8_t out[], size_t len) = 0;

      /**
      * Write keystream bytes to a buffer
      */
      virtual void generate_keystream(uint8_t out[], size_t len);

      /**
      * Resync the cipher using the IV
      */
      virtual void set_iv_bytes(const uint8_t iv[], size_t iv_len) = 0;
};

}  // namespace Botan

namespace Botan {

template <typename T, typename Tag, typename... Capabilities>
class Strong;

/**
 * Trait that detects whether the given types are a Strong<> instantiation
 */
template <typename... Ts>
struct is_strong_type : std::false_type {};

/// @copydoc is_strong_type
template <typename... Ts>
struct is_strong_type<Strong<Ts...>> : std::true_type {};

template <typename... Ts>
constexpr bool is_strong_type_v = is_strong_type<std::remove_const_t<Ts>...>::value;

namespace concepts {

template <typename T>
concept streamable = requires(std::ostream& os, T a) { os << a; };

template <class T>
concept strong_type = is_strong_type_v<T>;

template <class T>
concept contiguous_strong_type = strong_type<T> && contiguous_container<T>;

template <class T>
concept integral_strong_type = strong_type<T> && std::integral<typename T::wrapped_type>;

template <class T>
concept unsigned_integral_strong_type = strong_type<T> && std::unsigned_integral<typename T::wrapped_type>;

template <typename T, typename Capability>
concept strong_type_with_capability = T::template has_capability<Capability>();

}  // namespace concepts

/**
 * Added as an additional "capability tag" to enable arithmetic operators with
 * plain numbers for Strong<> types that wrap a number.
 */
struct EnableArithmeticWithPlainNumber {};

namespace detail {

/**
 * Checks whether the @p CapabilityT is included in the @p Tags type pack.
 */
template <typename CapabilityT, typename... Tags>
constexpr bool has_capability = (std::is_same_v<CapabilityT, Tags> || ...);

/**
 * Storage for the wrapped value of a strong type, and access to it via get()
 */
template <typename T>
class Strong_Base {
   private:
      T m_value;

   public:
      /// The type wrapped by this strong type
      using wrapped_type = T;

   public:
      /// Default constructor, value initializes the wrapped value
      Strong_Base() = default;

      /// Copy constructor
      Strong_Base(const Strong_Base&) = default;

      /// Move constructor
      Strong_Base(Strong_Base&&) noexcept = default;

      /// Copy assignment
      /// @return reference to this
      Strong_Base& operator=(const Strong_Base&) = default;

      /// Move assignment
      /// @return reference to this
      Strong_Base& operator=(Strong_Base&&) noexcept = default;

      ~Strong_Base() = default;

      /// Wrap the given value
      /// @param v the value to wrap
      constexpr explicit Strong_Base(T v) : m_value(std::move(v)) {}

      /// Access the wrapped value
      /// @return reference to the wrapped value
      constexpr T& get() & { return m_value; }

      /// Access the wrapped value
      /// @return const reference to the wrapped value
      constexpr const T& get() const& { return m_value; }

      /// Access the wrapped value
      /// @return rvalue reference to the wrapped value
      constexpr T&& get() && { return std::move(m_value); }

      /// Access the wrapped value
      /// @return const rvalue reference to the wrapped value
      constexpr const T&& get() const&& { return std::move(m_value); }
};

/**
 * Adds functionality to Strong_Base depending on the wrapped type
 *
 * The primary template adds nothing; the specializations below expose
 * container and contiguous container operations where applicable.
 */
template <typename T>
class Strong_Adapter : public Strong_Base<T> {
   public:
      using Strong_Base<T>::Strong_Base;
};

template <std::integral T>
class Strong_Adapter<T> : public Strong_Base<T> {
   public:
      using Strong_Base<T>::Strong_Base;
};

/**
 * Forwards the container interface of the wrapped type
 */
template <concepts::container T>
class Container_Strong_Adapter_Base : public Strong_Base<T> {
   public:
      /// The element type of the wrapped container
      using value_type = typename T::value_type;

      /// The size type of the wrapped container
      using size_type = typename T::size_type;

      /// The iterator type of the wrapped container
      using iterator = typename T::iterator;

      /// The const iterator type of the wrapped container
      using const_iterator = typename T::const_iterator;

   public:
      using Strong_Base<T>::Strong_Base;

      /// Create a container holding the given number of default constructed elements
      /// @param size the number of elements
      explicit Container_Strong_Adapter_Base(size_t size)
         requires(concepts::resizable_container<T>)
            : Container_Strong_Adapter_Base(T(size)) {}

      /// Create a container from the elements of an iterator range
      /// @param begin start of the range
      /// @param end one past the end of the range
      template <typename InputIt>
      Container_Strong_Adapter_Base(InputIt begin, InputIt end) : Container_Strong_Adapter_Base(T(begin, end)) {}

   public:
      /// Iterate the wrapped container
      /// @return an iterator to the first element
      decltype(auto) begin() noexcept(noexcept(this->get().begin())) { return this->get().begin(); }

      /// Iterate the wrapped container
      /// @return a const iterator to the first element
      decltype(auto) begin() const noexcept(noexcept(this->get().begin())) { return this->get().begin(); }

      /// Iterate the wrapped container
      /// @return an iterator one past the last element
      decltype(auto) end() noexcept(noexcept(this->get().end())) { return this->get().end(); }

      /// Iterate the wrapped container
      /// @return a const iterator one past the last element
      decltype(auto) end() const noexcept(noexcept(this->get().end())) { return this->get().end(); }

      /// Iterate the wrapped container
      /// @return a const iterator to the first element
      decltype(auto) cbegin() noexcept(noexcept(this->get().cbegin())) { return this->get().cbegin(); }

      /// Iterate the wrapped container
      /// @return a const iterator to the first element
      decltype(auto) cbegin() const noexcept(noexcept(this->get().cbegin())) { return this->get().cbegin(); }

      /// Iterate the wrapped container
      /// @return a const iterator one past the last element
      decltype(auto) cend() noexcept(noexcept(this->get().cend())) { return this->get().cend(); }

      /// Iterate the wrapped container
      /// @return a const iterator one past the last element
      decltype(auto) cend() const noexcept(noexcept(this->get().cend())) { return this->get().cend(); }

      /// Query the size of the wrapped container
      /// @return the number of elements
      size_type size() const noexcept(noexcept(this->get().size())) { return this->get().size(); }

      /// Query whether the wrapped container is empty
      /// @return true if the container holds no elements
      bool empty() const noexcept(noexcept(this->get().empty()))
         requires(concepts::has_empty<T>)
      {
         return this->get().empty();
      }

      /// Change the number of elements held
      /// @param size the new number of elements
      void resize(size_type size) noexcept(noexcept(this->get().resize(size)))
         requires(concepts::resizable_container<T>)
      {
         this->get().resize(size);
      }

      /// Preallocate storage for the given number of elements
      /// @param size the number of elements to reserve capacity for
      void reserve(size_type size) noexcept(noexcept(this->get().reserve(size)))
         requires(concepts::reservable_container<T>)
      {
         this->get().reserve(size);
      }

      /// Element access
      /// @param i the index of the element
      /// @return const reference to the element at index i
      template <typename U>
      decltype(auto) operator[](U&& i) const noexcept(noexcept(this->get().operator[](i))) {
         return this->get()[std::forward<U>(i)];
      }

      /// Element access
      /// @param i the index of the element
      /// @return reference to the element at index i
      template <typename U>
      decltype(auto) operator[](U&& i) noexcept(noexcept(this->get().operator[](i))) {
         return this->get()[std::forward<U>(i)];
      }
};

template <concepts::container T>
class Strong_Adapter<T> : public Container_Strong_Adapter_Base<T> {
   public:
      using Container_Strong_Adapter_Base<T>::Container_Strong_Adapter_Base;
};

template <concepts::contiguous_container T>
class Strong_Adapter<T> : public Container_Strong_Adapter_Base<T> {
   public:
      using pointer = typename T::pointer;
      using const_pointer = typename T::const_pointer;

   public:
      using Container_Strong_Adapter_Base<T>::Container_Strong_Adapter_Base;

      explicit Strong_Adapter(std::span<const typename Container_Strong_Adapter_Base<T>::value_type> span) :
            Strong_Adapter(T(span.begin(), span.end())) {}

      // Disambiguates the usage of string literals, otherwise:
      // Strong_Adapter(std::span<>) and Strong_Adapter(const char*)
      // would be ambiguous.
      explicit Strong_Adapter(const char* str)
         requires(std::same_as<T, std::string>)
            : Strong_Adapter(std::string(str)) {}

   public:
      decltype(auto) data() noexcept(noexcept(this->get().data())) { return this->get().data(); }

      decltype(auto) data() const noexcept(noexcept(this->get().data())) { return this->get().data(); }
};

}  // namespace detail

/**
 * Strong types can be used as wrappers around common types to provide
 * compile time semantics. They usually contribute to more maintainable and
 * less error-prone code especially when dealing with function parameters.
 *
 * Internally, this provides adapters so that the wrapping strong type behaves
 * as much as the underlying type as possible and desirable.
 *
 * This implementation was inspired by:
 *   https://stackoverflow.com/a/69030899
 */
template <typename T, typename TagTypeT, typename... Capabilities>
class Strong final : public detail::Strong_Adapter<T> {
   public:
      using detail::Strong_Adapter<T>::Strong_Adapter;

      /**
      * Check whether this strong type was declared with the given capability tag
      * @return true if CapabilityT is one of this type's Capabilities
      */
      template <typename CapabilityT>
      constexpr static bool has_capability() {
         return (std::is_same_v<CapabilityT, Capabilities> || ...);
      }

   private:
      using Tag = TagTypeT;
};

/**
 * @brief Generically unwraps a strong type to its underlying type.
 *
 * If the provided type is not a strong type, it is returned as is.
 *
 * @note This is meant as a helper for generic code that needs to deal with both
 *       wrapped strong types and bare objects. Use the ordinary `get()` method
 *       if you know that you are dealing with a strong type.
 *
 * @param t  value to be unwrapped
 * @return   the unwrapped value
 */
template <typename T>
[[nodiscard]] constexpr decltype(auto) unwrap_strong_type(T&& t) {
   if constexpr(!concepts::strong_type<std::remove_cvref_t<T>>) {
      // If the parameter type isn't a strong type, return it as is.
      return std::forward<T>(t);
   } else {
      // Unwrap the strong type and return the underlying value.
      return std::forward<T>(t).get();
   }
}

/**
 * @brief Wraps a value into a caller-defined (strong) type.
 *
 * If the provided object @p t is already of type @p T, it is returned as is.
 *
 * @note This is meant as a helper for generic code that needs to deal with both
 *       wrapped strong types and bare objects. Use the ordinary constructor if
 *       you know that you are dealing with a bare value type.
 *
 * @param t  value to be wrapped
 * @return   the wrapped value
 */
template <typename T, typename ParamT>
   requires std::constructible_from<T, ParamT> ||
            (concepts::strong_type<T> && std::constructible_from<typename T::wrapped_type, ParamT>)
[[nodiscard]] constexpr decltype(auto) wrap_strong_type(ParamT&& t) {
   if constexpr(std::same_as<std::remove_cvref_t<ParamT>, T>) {
      // Noop, if the parameter type already is the desired return type.
      return std::forward<ParamT>(t);
   } else if constexpr(std::constructible_from<T, ParamT>) {
      // Implicit conversion from the parameter type to the return type.
      return T{std::forward<ParamT>(t)};
   } else {
      // Explicitly calling the wrapped type's constructor to support
      // implicit conversions on types that mark their constructors as explicit.
      static_assert(concepts::strong_type<T> && std::constructible_from<typename T::wrapped_type, ParamT>);
      return T{typename T::wrapped_type{std::forward<ParamT>(t)}};
   }
}

namespace detail {

/**
 * Resolves to the type wrapped by a strong type, or to T itself if T is
 * not a strong type
 */
template <typename T>
struct wrapped_type_helper {
      /// The resolved type
      using type = T;
};

/// @copydoc wrapped_type_helper
template <concepts::strong_type T>
struct wrapped_type_helper<T> {
      /// The resolved type
      using type = typename T::wrapped_type;
};

}  // namespace detail

/**
 * @brief Extracts the wrapped type from a strong type.
 *
 * If the provided type is not a strong type, it is returned as is.
 *
 * @note This is meant as a helper for generic code that needs to deal with both
 *       wrapped strong types and bare objects. Use the ordinary `::wrapped_type`
 *       declaration if you know that you are dealing with a strong type.
 */
template <typename T>
using strong_type_wrapped_type = typename detail::wrapped_type_helper<std::remove_cvref_t<T>>::type;

/**
 * Write the wrapped value to an output stream
 * @param os the output stream
 * @param v the strong type to write
 * @return reference to the output stream
 */
template <typename T, typename... Tags>
   requires(concepts::streamable<T>)
decltype(auto) operator<<(std::ostream& os, const Strong<T, Tags...>& v) {
   return os << v.get();
}

/**
 * Compare for equality
 * @param lhs the first operand (strong type)
 * @param rhs the second operand (strong type)
 * @return true if lhs and rhs are equal
 */
template <typename T, typename... Tags>
   requires(std::equality_comparable<T>)
bool operator==(const Strong<T, Tags...>& lhs, const Strong<T, Tags...>& rhs) {
   return lhs.get() == rhs.get();
}

/**
 * Three-way comparison
 * @param lhs the first operand (strong type)
 * @param rhs the second operand (strong type)
 * @return the ordering of lhs relative to rhs
 */
template <typename T, typename... Tags>
   requires(std::three_way_comparable<T>)
auto operator<=>(const Strong<T, Tags...>& lhs, const Strong<T, Tags...>& rhs) {
   return lhs.get() <=> rhs.get();
}

/**
 * Three-way comparison
 * @param a the first operand (plain number)
 * @param b the second operand (strong type)
 * @return the ordering of a relative to b
 */
template <std::integral T1, std::integral T2, typename... Tags>
auto operator<=>(T1 a, Strong<T2, Tags...> b) {
   return a <=> b.get();
}

/**
 * Three-way comparison
 * @param a the first operand (strong type)
 * @param b the second operand (plain number)
 * @return the ordering of a relative to b
 */
template <std::integral T1, std::integral T2, typename... Tags>
auto operator<=>(Strong<T1, Tags...> a, T2 b) {
   return a.get() <=> b;
}

/**
 * Compare for equality
 * @param a the first operand (plain number)
 * @param b the second operand (strong type)
 * @return true if a and b are equal
 */
template <std::integral T1, std::integral T2, typename... Tags>
auto operator==(T1 a, Strong<T2, Tags...> b) {
   return a == b.get();
}

/**
 * Compare for equality
 * @param a the first operand (strong type)
 * @param b the second operand (plain number)
 * @return true if a and b are equal
 */
template <std::integral T1, std::integral T2, typename... Tags>
auto operator==(Strong<T1, Tags...> a, T2 b) {
   return a.get() == b;
}

/**
 * Add the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator+(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a + b.get());
}

/**
 * Add the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator+(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() + b);
}

/**
 * Add the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator+(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() + b.get());
}

/**
 * Subtract the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator-(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a - b.get());
}

/**
 * Subtract the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator-(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() - b);
}

/**
 * Subtract the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator-(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() - b.get());
}

/**
 * Multiply the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator*(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a * b.get());
}

/**
 * Multiply the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator*(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() * b);
}

/**
 * Multiply the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator*(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() * b.get());
}

/**
 * Divide the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator/(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a / b.get());
}

/**
 * Divide the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator/(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() / b);
}

/**
 * Divide the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator/(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() / b.get());
}

/**
 * Bitwise XOR of the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator^(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a ^ b.get());
}

/**
 * Bitwise XOR of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator^(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() ^ b);
}

/**
 * Bitwise XOR of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator^(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() ^ b.get());
}

/**
 * Bitwise AND of the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator&(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a & b.get());
}

/**
 * Bitwise AND of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator&(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() & b);
}

/**
 * Bitwise AND of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator&(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() & b.get());
}

/**
 * Bitwise OR of the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator|(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a | b.get());
}

/**
 * Bitwise OR of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator|(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() | b);
}

/**
 * Bitwise OR of the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator|(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() | b.get());
}

/**
 * Right shift the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator>>(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a >> b.get());
}

/**
 * Right shift the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator>>(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() >> b);
}

/**
 * Right shift the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator>>(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() >> b.get());
}

/**
 * Left shift the wrapped values
 * @param a the left hand operand (plain number)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator<<(T1 a, Strong<T2, Tags...> b) {
   return Strong<T2, Tags...>(a << b.get());
}

/**
 * Left shift the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (plain number)
 * @return the result, wrapped in the strong type
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr decltype(auto) operator<<(Strong<T1, Tags...> a, T2 b) {
   return Strong<T1, Tags...>(a.get() << b);
}

/**
 * Left shift the wrapped values
 * @param a the left hand operand (strong type)
 * @param b the right hand operand (strong type)
 * @return the result, wrapped in the strong type
 */
template <std::integral T, typename... Tags>
constexpr decltype(auto) operator<<(Strong<T, Tags...> a, Strong<T, Tags...> b) {
   return Strong<T, Tags...>(a.get() << b.get());
}

/**
 * Add to the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator+=(Strong<T1, Tags...>& a, T2 b) {
   a.get() += b;
   return a;
}

/**
 * Add to the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator+=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() += b.get();
   return a;
}

/**
 * Subtract from the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator-=(Strong<T1, Tags...>& a, T2 b) {
   a.get() -= b;
   return a;
}

/**
 * Subtract from the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator-=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() -= b.get();
   return a;
}

/**
 * Multiply in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator*=(Strong<T1, Tags...>& a, T2 b) {
   a.get() *= b;
   return a;
}

/**
 * Multiply in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator*=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() *= b.get();
   return a;
}

/**
 * Divide in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator/=(Strong<T1, Tags...>& a, T2 b) {
   a.get() /= b;
   return a;
}

/**
 * Divide in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator/=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() /= b.get();
   return a;
}

/**
 * Bitwise XOR in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator^=(Strong<T1, Tags...>& a, T2 b) {
   a.get() ^= b;
   return a;
}

/**
 * Bitwise XOR in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator^=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() ^= b.get();
   return a;
}

/**
 * Bitwise AND in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator&=(Strong<T1, Tags...>& a, T2 b) {
   a.get() &= b;
   return a;
}

/**
 * Bitwise AND in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator&=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() &= b.get();
   return a;
}

/**
 * Bitwise OR in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator|=(Strong<T1, Tags...>& a, T2 b) {
   a.get() |= b;
   return a;
}

/**
 * Bitwise OR in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator|=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() |= b.get();
   return a;
}

/**
 * Right shift in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator>>=(Strong<T1, Tags...>& a, T2 b) {
   a.get() >>= b;
   return a;
}

/**
 * Right shift in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator>>=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() >>= b.get();
   return a;
}

/**
 * Left shift in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (plain number)
 * @return reference to a
 */
template <std::integral T1, std::integral T2, typename... Tags>
   requires(detail::has_capability<EnableArithmeticWithPlainNumber, Tags...>)
constexpr auto operator<<=(Strong<T1, Tags...>& a, T2 b) {
   a.get() <<= b;
   return a;
}

/**
 * Left shift in place the wrapped value
 * @param a the strong type to modify
 * @param b the right hand operand (strong type)
 * @return reference to a
 */
template <std::integral T, typename... Tags>
constexpr auto operator<<=(Strong<T, Tags...>& a, Strong<T, Tags...> b) {
   a.get() <<= b.get();
   return a;
}

/**
 * Increment the wrapped value (postfix)
 * @param a the strong type to modify
 * @return the value before the operation
 */
template <std::integral T, typename... Tags>
constexpr auto operator++(Strong<T, Tags...>& a, int) {
   auto tmp = a;
   ++a.get();
   return tmp;
}

/**
 * Increment the wrapped value (prefix)
 * @param a the strong type to modify
 * @return the value after the operation
 */
template <std::integral T, typename... Tags>
constexpr auto operator++(Strong<T, Tags...>& a) {
   ++a.get();
   return a;
}

/**
 * Decrement the wrapped value (postfix)
 * @param a the strong type to modify
 * @return the value before the operation
 */
template <std::integral T, typename... Tags>
constexpr auto operator--(Strong<T, Tags...>& a, int) {
   auto tmp = a;
   --a.get();
   return tmp;
}

/**
 * Decrement the wrapped value (prefix)
 * @param a the strong type to modify
 * @return the value after the operation
 */
template <std::integral T, typename... Tags>
constexpr auto operator--(Strong<T, Tags...>& a) {
   --a.get();
   return a;
}

/**
 * This mimics a std::span but keeps track of the strong-type information. Use
 * this when you would want to use `const Strong<...>&` as a parameter
 * declaration. In particular this allows assigning strong-type information to
 * slices of a bigger buffer without copying the bytes. E.g:
 *
 *    using Foo = Strong<std::vector<uint8_t>, Foo_>;
 *
 *    void bar(StrongSpan<Foo> foo) { ... }
 *
 *    std::vector<uint8_t> buffer;
 *    BufferSlicer slicer(buffer);
 *    bar(slicer.take<Foo>());  // This does not copy the data from buffer but
 *                              // just annotates the 'Foo' strong-type info.
 */
template <concepts::contiguous_strong_type T>
class StrongSpan final {
      using underlying_span = std::
         conditional_t<std::is_const_v<T>, std::span<const typename T::value_type>, std::span<typename T::value_type>>;

   public:
      /// The element type of the underlying span
      using value_type = typename underlying_span::value_type;

      /// The size type of the underlying span
      using size_type = typename underlying_span::size_type;

      /// The iterator type of the underlying span
      using iterator = typename underlying_span::iterator;

      /// The pointer type of the underlying span
      using pointer = typename underlying_span::pointer;

      /// The const pointer type of the underlying span
      using const_pointer = typename underlying_span::const_pointer;

      /// Default constructor, creates an empty span
      StrongSpan() = default;

      /// Annotate a plain span with this strong type's information
      /// @param span the span to annotate
      explicit StrongSpan(underlying_span span) : m_span(span) {}

      /// Create a span covering the contents of a strong type
      /// @param strong the strong type to view
      // NOLINTNEXTLINE(*-explicit-conversions)
      StrongSpan(T& strong) : m_span(strong) {}

      // Allows implicit conversion from `StrongSpan<T>` to `StrongSpan<const T>`.
      // Note that this is not bi-directional. Conversion from `StrongSpan<const T>`
      // to `StrongSpan<T>` is not allowed.
      //
      // TODO: Technically, we should be able to phrase this with a `requires std::is_const_v<T>`
      //       instead of the `std::enable_if` constructions. clang-tidy (14 or 15) doesn't seem
      //       to pick up on that (yet?). As a result, for a non-const T it assumes this to be
      //       a declaration of an ordinary copy constructor. The existence of a copy constructor
      //       is interpreted as "not cheap to copy", setting off the `performance-unnecessary-value-param` check.
      //       See also: https://github.com/randombit/botan/issues/3591
      /// Convert a StrongSpan<T> to a StrongSpan<const T>
      /// @param other the span to convert
      template <concepts::contiguous_strong_type T2>
      // NOLINTNEXTLINE(*-explicit-conversions)
      StrongSpan(const StrongSpan<T2>& other)
         requires(std::is_same_v<T2, std::remove_const_t<T>>)
            : m_span(other.get()) {}

      /// Copy constructor
      /// @param other the span to copy
      StrongSpan(const StrongSpan& other) = default;

      /// Move constructor
      /// @param other the span to move from
      StrongSpan(StrongSpan&& other) = default;

      /// Copy assignment
      /// @param other the span to copy
      /// @return reference to this
      StrongSpan& operator=(const StrongSpan& other) = default;

      /// Move assignment
      /// @param other the span to move from
      /// @return reference to this
      StrongSpan& operator=(StrongSpan&& other) = default;

      ~StrongSpan() = default;

      /**
       * Access the underlying span
       * @returns the underlying std::span without any type constraints
       */
      underlying_span get() const { return m_span; }

      /**
       * Access the underlying span
       * @returns the underlying std::span without any type constraints
       */
      underlying_span get() { return m_span; }

      /// Access the underlying storage
      /// @return a pointer to the first element
      decltype(auto) data() noexcept(noexcept(this->m_span.data())) { return this->m_span.data(); }

      /// Access the underlying storage
      /// @return a const pointer to the first element
      decltype(auto) data() const noexcept(noexcept(this->m_span.data())) { return this->m_span.data(); }

      /// Query the size of the span
      /// @return the number of elements
      decltype(auto) size() const noexcept(noexcept(this->m_span.size())) { return this->m_span.size(); }

      /// Query whether the span is empty
      /// @return true if the span covers no elements
      bool empty() const noexcept(noexcept(this->m_span.empty())) { return this->m_span.empty(); }

      /// Iterate the span
      /// @return an iterator to the first element
      decltype(auto) begin() noexcept(noexcept(this->m_span.begin())) { return this->m_span.begin(); }

      /// Iterate the span
      /// @return a const iterator to the first element
      decltype(auto) begin() const noexcept(noexcept(this->m_span.begin())) { return this->m_span.begin(); }

      /// Iterate the span
      /// @return an iterator one past the last element
      decltype(auto) end() noexcept(noexcept(this->m_span.end())) { return this->m_span.end(); }

      /// Iterate the span
      /// @return a const iterator one past the last element
      decltype(auto) end() const noexcept(noexcept(this->m_span.end())) { return this->m_span.end(); }

      /// Element access
      /// @param i the index of the element
      /// @return reference to the element at index i
      decltype(auto) operator[](typename underlying_span::size_type i) const noexcept { return this->m_span[i]; }

   private:
      underlying_span m_span;
};

/**
 * Trait that detects whether the given type is a StrongSpan<> instantiation
 */
template <typename>
struct is_strong_span : std::false_type {};

/// @copydoc is_strong_span
template <typename T>
struct is_strong_span<StrongSpan<T>> : std::true_type {};

template <typename T>
constexpr bool is_strong_span_v = is_strong_span<T>::value;

}  // namespace Botan

namespace Botan {

/**
* Return a shared reference to a global PRNG instance provided by the
* operating system. For instance might be instantiated by /dev/urandom
* or CryptGenRandom.
*/
BOTAN_PUBLIC_API(2, 0) RandomNumberGenerator& system_rng();

/**
* Instantiable reference to the system RNG.
*/
class BOTAN_PUBLIC_API(2, 0) System_RNG final : public RandomNumberGenerator {
   public:
      /**
      * Return the name of this RNG type
      * @return the name of this RNG type
      */
      std::string name() const override { return system_rng().name(); }

      /**
      * Test whether this RNG has been seeded
      * @return true if this RNG is seeded and ready for use
      */
      bool is_seeded() const override { return system_rng().is_seeded(); }

      /**
      * Test whether this RNG accepts externally provided input
      * @return false if this RNG is known to ignore provided inputs
      */
      bool accepts_input() const override { return system_rng().accepts_input(); }

      /**
      * Clear all internally held values of this RNG
      */
      void clear() override { system_rng().clear(); }

   protected:
      /**
      * Fill the output buffer, first incorporating the provided input
      * @param out the buffer to fill
      * @param in additional input to incorporate
      */
      void fill_bytes_with_input(std::span<uint8_t> out, std::span<const uint8_t> in) override {
         system_rng().randomize_with_input(out, in);
      }
};

}  // namespace Botan

namespace Botan {

/*
* Get information describing the version
*/

/**
* Get a human-readable single-line string identifying the version of Botan.
* No particular format should be assumed.
* @return version string
*/
BOTAN_PUBLIC_API(2, 0) std::string version_string();

/**
* Same as version_string() except returning a pointer to a statically
* allocated string.
* @return version string
*/
BOTAN_PUBLIC_API(2, 0) const char* version_cstr();

/**
* Return a version string of the form "MAJOR.MINOR.PATCH" where
* each of the values is an integer.
*/
BOTAN_PUBLIC_API(2, 4) std::string short_version_string();

/**
* Same as version_short_string except returning a pointer to the string.
*/
BOTAN_PUBLIC_API(2, 4) const char* short_version_cstr();

/**
* Return the date this version of botan was released, in an integer of
* the form YYYYMMDD. For instance a version released on May 21, 2013
* would return the integer 20130521. If the currently running version
* is not an official release, this function will return 0 instead.
*
* @return release date, or zero if unreleased
*/
BOTAN_PUBLIC_API(2, 0) uint32_t version_datestamp();

/**
* Get the major version number.
* @return major version number
*/
BOTAN_PUBLIC_API(2, 0) uint32_t version_major();

/**
* Get the minor version number.
* @return minor version number
*/
BOTAN_PUBLIC_API(2, 0) uint32_t version_minor();

/**
* Get the patch number.
* @return patch number
*/
BOTAN_PUBLIC_API(2, 0) uint32_t version_patch();

/**
* Returns a string that is set to a revision identifier corresponding to the
* source, or `nullopt` if this could not be determined. It is set for all
* official releases, and for builds that originated from within a git checkout.
*
* @return VC revision
*/
BOTAN_PUBLIC_API(3, 8) std::optional<std::string> version_vc_revision();

/**
* Return any string that is set at build time using the `--distribution-info`
* option. It allows a packager of the library to specify any distribution-specific
* patches. If no value is given at build time, returns `nullopt`.
*
* @return distribution info
*/
BOTAN_PUBLIC_API(3, 8) std::optional<std::string> version_distribution_info();

/**
* Usable for checking that the DLL version loaded at runtime exactly matches the
* compile-time version. Call using BOTAN_VERSION_* macro values, like so:
*
* ```
* Botan::runtime_version_check(BOTAN_VERSION_MAJOR, BOTAN_VERSION_MINOR, BOTAN_VERSION_PATCH);
* ```
*
* It will return an empty string if the versions match, or otherwise an error
* message indicating the discrepancy. This only is useful in dynamic libraries,
* where it is possible to compile and run against different versions.
*/
BOTAN_PUBLIC_API(2, 0) std::string runtime_version_check(uint32_t major, uint32_t minor, uint32_t patch);

/**
* Certain build-time options, used for testing, result in a binary which is not
* safe for use in a production system. This function can be used to test for such
* a configuration at runtime.
*
* Currently these unsafe conditions include:
*
* - Unsafe fuzzer mode (--unsafe-fuzzer-mode) which intentionally disables various
*   checks in order to improve the effectiveness of fuzzing.
* - Terminate on asserts (--unsafe-terminate-on-asserts) which intentionally aborts
*   if any internal assertion failure occurs, rather than throwing an exception.
*/
BOTAN_PUBLIC_API(3, 8) bool unsafe_for_production_build();

// NOLINTBEGIN(*-macro-usage)

/*
* Macros for compile-time version checks
*
* Return a value that can be used to compare versions. The current
* (compile-time) version is available as the macro BOTAN_VERSION_CODE. For
* instance, to choose one code path for version 3.1.0 and later, and another
* code path for older releases:
*
* ```
* #if BOTAN_VERSION_CODE >= BOTAN_VERSION_CODE_FOR(3,1,0)
*    // 3.1+ code path
* #else
*    // code path for older versions
* #endif
* ```
*/
#define BOTAN_VERSION_CODE_FOR(a, b, c) (((a) << 16) | ((b) << 8) | (c))

/**
* Compare using BOTAN_VERSION_CODE_FOR, as in
*  # if BOTAN_VERSION_CODE < BOTAN_VERSION_CODE_FOR(1,8,0)
*  #    error "Botan version too old"
*  # endif
*/
#define BOTAN_VERSION_CODE BOTAN_VERSION_CODE_FOR(BOTAN_VERSION_MAJOR, BOTAN_VERSION_MINOR, BOTAN_VERSION_PATCH)

// NOLINTEND(*-macro-usage)

}  // namespace Botan

#endif // BOTAN_AMALGAMATION_H_
