/*
* Botan 3.13.0 Amalgamation
* (C) 1999-2023 The Botan Authors
*
* Botan is released under the Simplified BSD License (see license.txt)
*/

#include "botan_all.h"

#include <array>
#include <bit>
#include <chrono>
#include <concepts>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <functional>
#include <iosfwd>
#include <iterator>
#include <locale>
#include <map>
#include <memory>
#include <optional>
#include <ranges>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>


namespace Botan {

/**
* AES-128
*/
class AES_128 final : public Block_Cipher_Fixed_Params<16, 16> {
   public:
      void encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;
      void decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;

      void clear() override;

      std::string provider() const override;

      std::string name() const override { return "AES-128"; }

      std::unique_ptr<BlockCipher> new_object() const override { return std::make_unique<AES_128>(); }

      size_t parallelism() const override;

      bool has_keying_material() const override;

   private:
      void key_schedule(std::span<const uint8_t> key) override;

#if defined(BOTAN_HAS_AES_VPERM)
      void vperm_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_NI)
      void aesni_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_POWER8) || defined(BOTAN_HAS_AES_ARMV8) || defined(BOTAN_HAS_AES_NI)
      void hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

#if defined(BOTAN_HAS_AES_VAES)
      void x86_vaes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void x86_vaes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

      secure_vector<uint32_t> m_EK, m_DK;
};

/**
* AES-192
*/
class AES_192 final : public Block_Cipher_Fixed_Params<16, 24> {
   public:
      void encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;
      void decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;

      void clear() override;

      std::string provider() const override;

      std::string name() const override { return "AES-192"; }

      std::unique_ptr<BlockCipher> new_object() const override { return std::make_unique<AES_192>(); }

      size_t parallelism() const override;
      bool has_keying_material() const override;

   private:
#if defined(BOTAN_HAS_AES_VPERM)
      void vperm_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_NI)
      void aesni_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_POWER8) || defined(BOTAN_HAS_AES_ARMV8) || defined(BOTAN_HAS_AES_NI)
      void hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

#if defined(BOTAN_HAS_AES_VAES)
      void x86_vaes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void x86_vaes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

      void key_schedule(std::span<const uint8_t> key) override;

      secure_vector<uint32_t> m_EK, m_DK;
};

/**
* AES-256
*/
class AES_256 final : public Block_Cipher_Fixed_Params<16, 32> {
   public:
      void encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;
      void decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const override;

      void clear() override;

      std::string provider() const override;

      std::string name() const override { return "AES-256"; }

      std::unique_ptr<BlockCipher> new_object() const override { return std::make_unique<AES_256>(); }

      size_t parallelism() const override;
      bool has_keying_material() const override;

   private:
#if defined(BOTAN_HAS_AES_VPERM)
      void vperm_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void vperm_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_NI)
      void aesni_key_schedule(const uint8_t key[], size_t length);
#endif

#if defined(BOTAN_HAS_AES_POWER8) || defined(BOTAN_HAS_AES_ARMV8) || defined(BOTAN_HAS_AES_NI)
      void hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

#if defined(BOTAN_HAS_AES_VAES)
      void x86_vaes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
      void x86_vaes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const;
#endif

      void key_schedule(std::span<const uint8_t> key) override;

      secure_vector<uint32_t> m_EK, m_DK;
};

}  // namespace Botan

namespace Botan {

/**
 * Helper class to ease unmarshalling of concatenated fixed-length values
 */
class BufferSlicer final {
   public:
      explicit BufferSlicer(std::span<const uint8_t> buffer) : m_remaining(buffer) {}

      template <concepts::contiguous_container ContainerT>
      auto copy(const size_t count) {
         const auto result = take(count);
         return ContainerT(result.begin(), result.end());
      }

      auto copy_as_vector(const size_t count) { return copy<std::vector<uint8_t>>(count); }

      auto copy_as_secure_vector(const size_t count) { return copy<secure_vector<uint8_t>>(count); }

      std::span<const uint8_t> take(const size_t count) {
         BOTAN_STATE_CHECK(remaining() >= count);
         auto result = m_remaining.first(count);
         m_remaining = m_remaining.subspan(count);
         return result;
      }

      template <size_t count>
      std::span<const uint8_t, count> take() {
         BOTAN_STATE_CHECK(remaining() >= count);
         auto result = m_remaining.first<count>();
         m_remaining = m_remaining.subspan(count);
         return result;
      }

      template <concepts::contiguous_strong_type T>
      StrongSpan<const T> take(const size_t count) {
         return StrongSpan<const T>(take(count));
      }

      uint8_t take_byte() { return take(1)[0]; }

      void copy_into(std::span<uint8_t> sink) {
         const auto data = take(sink.size());
         std::copy(data.begin(), data.end(), sink.begin());
      }

      void skip(const size_t count) { take(count); }

      size_t remaining() const { return m_remaining.size(); }

      bool empty() const { return m_remaining.empty(); }

   private:
      std::span<const uint8_t> m_remaining;
};

}  // namespace Botan

namespace Botan {

/**
* Zeroize memory contents in a way that a compiler should not elide,
* using some system specific technique.
*
* Use this function to scrub memory just before deallocating it, or on
* a stack buffer before returning from the function.
*
* @param ptr a pointer to memory to scrub
* @param n the number of bytes pointed to by ptr
*/
BOTAN_TEST_API void secure_zeroize_buffer(void* ptr, size_t n);

/**
 * @param buf a pointer to the start of the region
 * @param n the number of elements in buf
 */
template <std::unsigned_integral T>
inline void zeroize_buffer(T buf[], size_t n) {
   if(n > 0) {
      std::memset(buf, 0, sizeof(T) * n);
   }
}

template <std::unsigned_integral T>
inline void unchecked_copy_memory(T* out, const T* in, size_t n) {
   if(in != nullptr && out != nullptr && n > 0) {
      std::memmove(out, in, sizeof(T) * n);
   }
}

/**
* Return true if any of the provided arguments are null
*/
template <typename... Ptrs>
bool any_null_pointers(Ptrs... ptr) {
   static_assert((... && std::is_pointer_v<Ptrs>), "All arguments must be pointers");
   return (... || (ptr == nullptr));
}

inline std::span<const uint8_t> as_span_of_bytes(const char* s, size_t len) {
   const uint8_t* b = reinterpret_cast<const uint8_t*>(s);
   return std::span{b, len};
}

inline std::span<const uint8_t> as_span_of_bytes(const std::string& s) {
   return as_span_of_bytes(s.data(), s.size());
}

inline std::span<const uint8_t> as_span_of_bytes(std::string_view s) {
   return as_span_of_bytes(s.data(), s.size());
}

inline std::span<const uint8_t> cstr_as_span_of_bytes(const char* s) {
   return as_span_of_bytes(s, std::strlen(s));
}

inline std::string bytes_to_string(std::span<const uint8_t> bytes) {
   return std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size());
}

}  // namespace Botan

namespace Botan {

/**
 * Defines the strategy for handling the final block of input data in the
 * handle_unaligned_data() method of the AlignmentBuffer<>.
 *
 * - is_not_special:   the final block is treated like any other block
 * - must_be_deferred: the final block is not emitted while bulk processing (typically add_data())
 *                     but is deferred until manually consumed (typically final_result())
 *
 * The AlignmentBuffer<> assumes data to be "the final block" if no further
 * input data is available in the BufferSlicer<>. This might result in some
 * performance overhead when using the must_be_deferred strategy.
 */
enum class AlignmentBufferFinalBlock : uint8_t {
   is_not_special = 0,
   must_be_deferred = 1,
};

/**
 * @brief Alignment buffer helper
 *
 * Many algorithms have an intrinsic block size in which they consume input
 * data. When streaming arbitrary data chunks to such algorithms we must store
 * some data intermittently to honor the algorithm's alignment requirements.
 *
 * This helper encapsulates such an alignment buffer. The API of this class is
 * designed to minimize user errors in the algorithm implementations. Therefore,
 * it is strongly opinionated on its use case. Don't try to use it for anything
 * but the described circumstance.
 *
 * @tparam T                     the element type of the internal buffer
 * @tparam BLOCK_SIZE            the buffer size to use for the alignment buffer
 * @tparam FINAL_BLOCK_STRATEGY  defines whether the final input data block is
 *                               retained in handle_unaligned_data() and must be
 *                               manually consumed
 */
template <typename T,
          size_t BLOCK_SIZE,
          AlignmentBufferFinalBlock FINAL_BLOCK_STRATEGY = AlignmentBufferFinalBlock::is_not_special>
   requires(BLOCK_SIZE > 0)
class AlignmentBuffer final {
   public:
      AlignmentBuffer() = default;

      ~AlignmentBuffer() { secure_zeroize_buffer(m_buffer.data(), sizeof(T) * m_buffer.size()); }

      AlignmentBuffer(const AlignmentBuffer& other) = default;
      AlignmentBuffer(AlignmentBuffer&& other) noexcept = default;
      AlignmentBuffer& operator=(const AlignmentBuffer& other) = default;
      AlignmentBuffer& operator=(AlignmentBuffer&& other) noexcept = default;

      void clear() {
         zeroize_buffer(m_buffer.data(), m_buffer.size());
         m_position = 0;
      }

      /**
       * Fills the currently unused bytes of the buffer with zero bytes
       */
      void fill_up_with_zeros() {
         if(!ready_to_consume()) {
            zeroize_buffer(&m_buffer[m_position], elements_until_alignment());
            m_position = m_buffer.size();
         }
      }

      /**
       * Appends the provided @p elements to the buffer. The user has to make
       * sure that @p elements fits in the remaining capacity of the buffer.
       */
      void append(std::span<const T> elements) {
         BOTAN_ASSERT_NOMSG(elements.size() <= elements_until_alignment());
         std::copy(elements.begin(), elements.end(), m_buffer.begin() + m_position);
         m_position += elements.size();
      }

      /**
       * Allows direct modification of the first @p elements in the buffer.
       * This is a low-level accessor that neither takes the buffer's current
       * capacity into account nor does it change the internal cursor.
       * Beware not to overwrite unconsumed bytes.
       */
      std::span<T> directly_modify_first(size_t elements) {
         BOTAN_ASSERT_NOMSG(size() >= elements);
         return std::span(m_buffer).first(elements);
      }

      /**
       * Allows direct modification of the last @p elements in the buffer.
       * This is a low-level accessor that neither takes the buffer's current
       * capacity into account nor does it change the internal cursor.
       * Beware not to overwrite unconsumed bytes.
       */
      std::span<T> directly_modify_last(size_t elements) {
         BOTAN_ASSERT_NOMSG(size() >= elements);
         return std::span(m_buffer).last(elements);
      }

      /**
       * Once the buffer reached alignment, this can be used to consume as many
       * input bytes from the given @p slider as possible. The output always
       * contains data elements that are a multiple of the intrinsic block size.
       *
       * @returns a view onto the aligned data from @p slicer and the number of
       *          full blocks that are represented by this view.
       */
      [[nodiscard]] std::tuple<std::span<const uint8_t>, size_t> aligned_data_to_process(BufferSlicer& slicer) const {
         BOTAN_ASSERT_NOMSG(in_alignment());

         // When the final block is to be deferred, the last block must not be
         // selected for processing if there is no (unaligned) extra input data.
         const size_t defer = (defers_final_block()) ? 1 : 0;
         const size_t full_blocks_to_process = (slicer.remaining() - defer) / m_buffer.size();
         return {slicer.take(full_blocks_to_process * m_buffer.size()), full_blocks_to_process};
      }

      /**
       * Once the buffer reached alignment, this can be used to consume full
       * blocks from the input data represented by @p slicer.
       *
       * @returns a view onto the next full block from @p slicer or std::nullopt
       *          if not enough data is available in @p slicer.
       */
      [[nodiscard]] std::optional<std::span<const uint8_t>> next_aligned_block_to_process(BufferSlicer& slicer) const {
         BOTAN_ASSERT_NOMSG(in_alignment());

         // When the final block is to be deferred, the last block must not be
         // selected for processing if there is no (unaligned) extra input data.
         const size_t defer = (defers_final_block()) ? 1 : 0;
         if(slicer.remaining() < m_buffer.size() + defer) {
            return std::nullopt;
         }

         return slicer.take(m_buffer.size());
      }

      /**
       * Intermittently buffers potentially unaligned data provided in @p
       * slicer. If the internal buffer already contains some elements, data is
       * appended. Once a full block is collected, it is returned to the caller
       * for processing.
       *
       * @param slicer the input data source to be (partially) consumed
       * @returns a view onto a full block once enough data was collected, or
       *          std::nullopt if no full block is available yet
       */
      [[nodiscard]] std::optional<std::span<const T>> handle_unaligned_data(BufferSlicer& slicer) {
         // When the final block is to be deferred, we would need to store and
         // hold a buffer that contains exactly one block until more data is
         // passed or it is explicitly consumed.
         const size_t defer = (defers_final_block()) ? 1 : 0;

         if(in_alignment() && slicer.remaining() >= m_buffer.size() + defer) {
            // We are currently in alignment and the passed-in data source
            // contains enough data to benefit from aligned processing.
            // Therefore, we don't copy anything into the intermittent buffer.
            return std::nullopt;
         }

         // Fill the buffer with as much input data as needed to reach alignment
         // or until the input source is depleted.
         const auto elements_to_consume = std::min(m_buffer.size() - m_position, slicer.remaining());
         append(slicer.take(elements_to_consume));

         // If we collected enough data, we push out one full block. When
         // deferring the final block is enabled, we additionally check that
         // more input data is available to continue processing a consecutive
         // block.
         if(ready_to_consume() && (!defers_final_block() || !slicer.empty())) {
            return consume();
         } else {
            return std::nullopt;
         }
      }

      /**
       * Explicitly consume the currently collected block. It is the caller's
       * responsibility to ensure that the buffer is filled fully. After
       * consumption, the buffer is cleared and ready to collect new data.
       */
      [[nodiscard]] std::span<const T> consume() {
         BOTAN_ASSERT_NOMSG(ready_to_consume());
         m_position = 0;
         return m_buffer;
      }

      /**
       * Explicitly consumes however many bytes are currently stored in the
       * buffer. After consumption, the buffer is cleared and ready to collect
       * new data.
       */
      [[nodiscard]] std::span<const T> consume_partial() {
         const auto elements = elements_in_buffer();
         m_position = 0;
         return std::span(m_buffer).first(elements);
      }

      constexpr size_t size() const { return m_buffer.size(); }

      size_t elements_in_buffer() const { return m_position; }

      size_t elements_until_alignment() const { return m_buffer.size() - m_position; }

      /**
       * @returns true if the buffer is empty (i.e. contains no unaligned data)
       */
      bool in_alignment() const { return m_position == 0; }

      /**
       * @returns true if the buffer is full (i.e. a block is ready to be consumed)
       */
      bool ready_to_consume() const { return m_position == m_buffer.size(); }

      constexpr bool defers_final_block() const {
         return FINAL_BLOCK_STRATEGY == AlignmentBufferFinalBlock::must_be_deferred;
      }

   private:
      std::array<T, BLOCK_SIZE> m_buffer = {};
      size_t m_position = 0;
};

}  // namespace Botan



namespace Botan {

/**
 * Swap the byte order of an unsigned integer
 */
template <std::unsigned_integral T>
   requires(sizeof(T) == 1 || sizeof(T) == 2 || sizeof(T) == 4 || sizeof(T) == 8)
inline constexpr T reverse_bytes(T x) {
   if constexpr(sizeof(T) == 1) {
      return x;
   } else if constexpr(sizeof(T) == 2) {
#if BOTAN_COMPILER_HAS_BUILTIN(__builtin_bswap16)
      return static_cast<T>(__builtin_bswap16(x));
#else
      return static_cast<T>((x << 8) | (x >> 8));
#endif
   } else if constexpr(sizeof(T) == 4) {
#if BOTAN_COMPILER_HAS_BUILTIN(__builtin_bswap32)
      return static_cast<T>(__builtin_bswap32(x));
#else
      // MSVC at least recognizes this as a bswap
      return static_cast<T>(((x & 0x000000FF) << 24) | ((x & 0x0000FF00) << 8) | ((x & 0x00FF0000) >> 8) |
                            ((x & 0xFF000000) >> 24));
#endif
   } else if constexpr(sizeof(T) == 8) {
#if BOTAN_COMPILER_HAS_BUILTIN(__builtin_bswap64)
      return static_cast<T>(__builtin_bswap64(x));
#else
      uint32_t hi = static_cast<uint32_t>(x >> 32);
      uint32_t lo = static_cast<uint32_t>(x);

      hi = reverse_bytes(hi);
      lo = reverse_bytes(lo);

      return (static_cast<T>(lo) << 32) | hi;
#endif
   }
}

}  // namespace Botan

/**
* @file  target_info.h
*
* Automatically generated from
* 'configure.py --amalgamation --minimized-build --enable-modules=argon2,argon2fmt,chacha20poly1305,chacha,poly1305,aes,aes_armv8,gcm,hmac,sha2_32,sha2_64,hkdf,pbkdf2,auto_rng,system_rng,hmac_drbg,base64,base32,hex,rfc3394 --disable-shared-library --without-documentation --cc=clang --os=macos --cpu=arm64'
*
* Target
*  - Compiler: clang++ -fstack-protector -pthread -stdlib=libc++ -std=c++20 -D_REENTRANT -O3
*  - Arch: arm64
*  - OS: macos
*/

/* NOLINTBEGIN(*-macro-usage,*-macro-to-enum) */

/*
* Configuration
*/
#define BOTAN_CT_VALUE_BARRIER_USE_ASM

[[maybe_unused]] static constexpr bool OptimizeForSize = false;



/*
* Compiler Information
*/
#define BOTAN_BUILD_COMPILER_IS_CLANG

#define BOTAN_COMPILER_INVOCATION_STRING "clang++ -fstack-protector -pthread -stdlib=libc++ -O3"

#define BOTAN_USE_GCC_INLINE_ASM


/*
* External tool settings
*/




/*
* CPU feature information
*/
#define BOTAN_TARGET_ARCH "arm64"

#define BOTAN_TARGET_ARCH_IS_ARM64

#define BOTAN_TARGET_ARCH_IS_ARM_FAMILY

#define BOTAN_TARGET_ARCH_SUPPORTS_ARMV8CRYPTO
#define BOTAN_TARGET_ARCH_SUPPORTS_ARMV8SHA512
#define BOTAN_TARGET_ARCH_SUPPORTS_ARMV8SM3
#define BOTAN_TARGET_ARCH_SUPPORTS_ARMV8SM4
#define BOTAN_TARGET_ARCH_SUPPORTS_NEON


/*
* Operating system information
*/
#define BOTAN_TARGET_OS_IS_MACOS

#define BOTAN_TARGET_OS_HAS_APPLE_KEYCHAIN
#define BOTAN_TARGET_OS_HAS_ARC4RANDOM
#define BOTAN_TARGET_OS_HAS_ATOMICS
#define BOTAN_TARGET_OS_HAS_CCRANDOM
#define BOTAN_TARGET_OS_HAS_CLOCK_GETTIME
#define BOTAN_TARGET_OS_HAS_COMMONCRYPTO
#define BOTAN_TARGET_OS_HAS_DEV_RANDOM
#define BOTAN_TARGET_OS_HAS_GETENTROPY
#define BOTAN_TARGET_OS_HAS_POSIX1
#define BOTAN_TARGET_OS_HAS_POSIX_MLOCK
#define BOTAN_TARGET_OS_HAS_SANDBOX_PROC
#define BOTAN_TARGET_OS_HAS_SOCKETS
#define BOTAN_TARGET_OS_HAS_SYSCTLBYNAME
#define BOTAN_TARGET_OS_HAS_SYSTEM_CLOCK
#define BOTAN_TARGET_OS_HAS_THREAD_LOCAL


/*
* System paths
*/
#define BOTAN_INSTALL_PREFIX R"(/usr/local)"
#define BOTAN_INSTALL_HEADER_DIR R"(include/botan-3)"
#define BOTAN_INSTALL_LIB_DIR R"(/usr/local/lib)"
#define BOTAN_LIB_LINK ""
#define BOTAN_LINK_FLAGS "-fstack-protector -pthread -stdlib=libc++"

#define BOTAN_SYSTEM_CERT_BUNDLE "/etc/ssl/cert.pem"

/* NOLINTEND(*-macro-usage,*-macro-to-enum) */

namespace Botan::CT {

/**
* This function returns its argument, but (if called in a non-constexpr context)
* attempts to prevent the compiler from reasoning about the value or the possible
* range of values. Such optimizations have a way of breaking constant time code.
*
* The method that is use is decided at configuration time based on the target
* compiler and architecture (see `ct_value_barrier` blocks in `src/build-data/cc`).
* The decision can be overridden by the user with the configure.py option
* `--ct-value-barrier-type=`
*
* There are three options currently possible in the data files and with the
* option:
*
*  * `asm`: Use an inline assembly expression which (currently) prevents Clang
*    and GCC from optimizing based on the possible value of the input expression.
*
*  * `volatile`: Launder the input through a volatile variable. This is likely
*    to cause significant performance regressions since the value must be
*    actually stored and loaded back from memory each time.
*
*  * `none`: disable constant time barriers entirely. This is used
*    with MSVC, which is not known to perform optimizations that break
*    constant time code and which does not support GCC-style inline asm.
*
*/
template <std::unsigned_integral T>
   requires(!std::same_as<bool, T>)
constexpr inline T value_barrier(T x) {
   if(std::is_constant_evaluated()) {
      return x;
   } else {
#if defined(BOTAN_CT_VALUE_BARRIER_USE_ASM)
      /*
      * We may want a "stronger" statement such as
      *     asm volatile("" : "+r,m"(x) : : "memory);
      * (see https://theunixzoo.co.uk/blog/2021-10-14-preventing-optimisations.html)
      * however the current approach seems sufficient with current compilers,
      * and is minimally damaging with regards to degrading code generation.
      */
      asm("" : "+r"(x) : /* no input */);  // NOLINT(*-no-assembler)
      return x;
#elif defined(BOTAN_CT_VALUE_BARRIER_USE_VOLATILE)
      volatile T vx = x;
      return vx;
#else
      return x;
#endif
   }
}

}  // namespace Botan::CT

namespace Botan {

/**
* If top bit of arg is set, return |1| (all bits set). Otherwise return |0| (all bits unset)
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T ct_expand_top_bit(T a) {
   const T top = CT::value_barrier<T>(a >> (sizeof(T) * 8 - 1));
   return static_cast<T>(0) - top;
}

/**
* If arg is zero, return |1|. Otherwise return |0|
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T ct_is_zero(T x) {
   return ct_expand_top_bit<T>(~x & (x - 1));
}

/**
* If arg is zero, return the size_t `s`. Otherwise return the size_t zero.
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr size_t ct_if_is_zero_ret(T x, size_t s) {
   /*
   Similar to `return ct_is_zero(x) & s` but has to account for possibility that
   sizeof(T) is smaller than sizeof(size_t) which would lead to incomplete masking
   */
   const T a = ~x & (x - 1);
   const size_t a_top = static_cast<size_t>(CT::value_barrier<T>(a >> (sizeof(T) * 8 - 1)));
   const size_t mask = static_cast<size_t>(0) - a_top;
   return mask & s;
}

/**
* Power of 2 test. T should be an unsigned integer type
* @param arg an integer value
* @return true iff arg is 2^n for some n > 0
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr bool is_power_of_2(T arg) {
   return (arg != 0) && (arg != 1) && ((arg & static_cast<T>(arg - 1)) == 0);
}

/**
* Return the index of the highest set bit
* T is an unsigned integer type
* @param n an integer value
* @return index of the highest set bit in n
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr size_t high_bit(T n) {
   size_t hb = 0;

   for(size_t s = 8 * sizeof(T) / 2; s > 0; s /= 2) {
      // Equivalent to: ((n >> s) == 0) ? 0 : s;
      const size_t z = s - ct_if_is_zero_ret<T>(n >> s, s);
      hb += z;
      n >>= z;
   }

   hb += n;

   return hb;
}

/**
* Return the number of significant bytes in n
* @param n an integer value
* @return number of significant bytes in n
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr size_t significant_bytes(T n) {
   size_t b = 0;

   for(size_t s = 8 * sizeof(T) / 2; s >= 8; s /= 2) {
      // Equivalent to: ((n >> s) == 0) ? 0 : s;
      const size_t z = s - ct_if_is_zero_ret<T>(n >> s, s);
      b += z / 8;
      n >>= z;
   }

   b += (n != 0);

   return b;
}

/**
* Count the trailing zero bits in n
* @param n an integer value
* @return maximum x st 2^x divides n
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr size_t ctz(T n) {
   /*
   * If n == 0 then this function will compute 8*sizeof(T)-1, so
   * initialize lb to 1 if n == 0 to produce the expected result.
   */
   size_t lb = ct_if_is_zero_ret<T>(n, 1);

   for(size_t s = 8 * sizeof(T) / 2; s > 0; s /= 2) {
      const T range = (static_cast<T>(1) << s) - 1;
      // Equivalent to: ((n & range) == 0) ? s : 0;
      const size_t z = ct_if_is_zero_ret<T>(n & range, s);
      lb += z;
      n >>= z;
   }

   return lb;
}

template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T floor_log2(T n) {
   BOTAN_ARG_CHECK(n != 0, "log2(0) is not defined");
   return static_cast<T>(high_bit(n) - 1);
}

template <std::unsigned_integral T>
constexpr uint8_t ceil_log2(T x)
   requires(sizeof(T) < 32)
{
   if(x >> (sizeof(T) * 8 - 1)) {
      return sizeof(T) * 8;
   }

   uint8_t result = 0;
   T compare = 1;

   while(compare < x) {
      compare <<= 1;
      result++;
   }

   return result;
}

/**
 * Ceil of an unsigned integer division. @p b must not be zero.
 *
 * @param a divident
 * @param b divisor
 *
 * @returns ceil(a/b)
 */
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T ceil_division(T a, T b) {
   return (a + b - 1) / b;
}

/**
 * Return the number of bytes necessary to contain @p bits bits.
 */
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T ceil_tobytes(T bits) {
   return (bits + 7) / 8;
}

// Potentially variable time ctz used for OCB
BOTAN_FORCE_INLINE constexpr size_t var_ctz64(uint64_t n) {
#if BOTAN_COMPILER_HAS_BUILTIN(__builtin_ctzll)
   if(n == 0) {
      return 64;
   }
   return __builtin_ctzll(n);
#else
   return ctz<uint64_t>(n);
#endif
}

template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T bit_permute_step(T x, T mask, size_t shift) {
   /*
   See https://reflectionsonsecurity.wordpress.com/2014/05/11/efficient-bit-permutation-using-delta-swaps/
   and http://programming.sirrida.de/bit_perm.html
   */
   const T swap = ((x >> shift) ^ x) & mask;
   return (x ^ swap) ^ (swap << shift);
}

template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr void swap_bits(T& x, T& y, T mask, size_t shift) {
   const T swap = ((x >> shift) ^ y) & mask;
   x ^= swap << shift;
   y ^= swap;
}

/**
* Bitwise selection
*
* If mask is |1| returns a
* If mask is |0| returns b
* If mask is some other value returns a or b depending on the bit
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T choose(T mask, T a, T b) {
   //return (mask & a) | (~mask & b);
   return (b ^ (mask & (a ^ b)));
}

template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T majority(T a, T b, T c) {
   /*
   Considering each bit of a, b, c individually

   If a xor b is set, then c is the deciding vote.

   If a xor b is not set then either a and b are both set or both unset.
   In either case the value of c doesn't matter, and examining b (or a)
   allows us to determine which case we are in.
   */
   return choose(a ^ b, c, b);
}

/**
 * @returns the reversed bits in @p b.
 */
template <std::unsigned_integral T>
inline constexpr T ct_reverse_bits(T b) {
   auto extend = [](uint8_t m) -> T {
      T mask = 0;
      for(size_t i = 0; i < sizeof(T); ++i) {
         mask |= T(m) << i * 8;
      }
      return mask;
   };

   // First reverse bits in each byte...
   // From: https://stackoverflow.com/a/2602885
   b = (b & extend(0xF0)) >> 4 | (b & extend(0x0F)) << 4;
   b = (b & extend(0xCC)) >> 2 | (b & extend(0x33)) << 2;
   b = (b & extend(0xAA)) >> 1 | (b & extend(0x55)) << 1;

   // ... then swap the bytes
   return reverse_bytes(b);
}

/**
 * Calculates the number of 1-bits in an unsigned integer in constant-time.
 * This operation is also known as "population count" or hamming weight.
 *
 * Modern compilers will recognize this pattern and replace it by a hardware
 * instruction, if available. This is the SWAR (SIMD within a register)
 * algorithm. See: https://nimrod.blog/posts/algorithms-behind-popcount/#swar-algorithm
 *
 * Note: C++20 provides std::popcount(), but there's no guarantee that this
 *       is implemented in constant-time.
 *
 * @param x an unsigned integer
 * @returns the number of 1-bits in the provided value
 */
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr uint8_t ct_popcount(T x) {
   constexpr size_t s = sizeof(T);
   static_assert(s <= 8, "T is not a suitable unsigned integer value");
   if constexpr(s == 8) {
      x = x - ((x >> 1) & 0x5555555555555555);
      x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
      x = (x + (x >> 4)) & 0xF0F0F0F0F0F0F0F;
      return (x * 0x101010101010101) >> 56;
   } else if constexpr(s == 4) {
      x = x - ((x >> 1) & 0x55555555);
      x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
      x = (x + (x >> 4)) & 0x0F0F0F0F;
      return (x * 0x01010101) >> 24;
   } else {
      // s < 4
      return ct_popcount(static_cast<uint32_t>(x));
   }
}

/**
* Compile-time polynomial multiplication in GF(2^8) modulo an irreducible
* polynomial POLY
*
* When T is larger than a byte, the function computes the product of each byte
* of T and returns the packed result.
*
* This function is intended only for use at compile-time, and in particular
* should not be used with secret inputs.
*
* TODO(Botan4) this function should be consteval, but that hits bugs in
* older versions of GCC and Clang.
*/
template <uint8_t POLY, std::unsigned_integral T>
constexpr T poly_mul(T x, uint8_t y) {
   // The constant 0x010101... as a T
   constexpr T lo_bit = (static_cast<T>(-1) / 255);

   // The constant 0x7F7F7F... as a T
   constexpr T mask = static_cast<T>(~(lo_bit << 7));

   constexpr T poly = POLY;

   T r = 0;
   while(x > 0 && y > 0) {
      if((y & 1) != 0) {
         r ^= x;
      }
      const T carry = ((x >> 7) & lo_bit) * poly;
      x = ((x & mask) << 1) ^ carry;
      y >>= 1;
   }
   return r;
}

}  // namespace Botan

namespace Botan {

constexpr size_t BLAKE2B_BLOCKBYTES = 128;

/**
* BLAKE2B
*/
class BLAKE2b final : public HashFunction,
                      public SymmetricAlgorithm {
   public:
      /**
      * @param output_bits the output size of BLAKE2b in bits
      */
      explicit BLAKE2b(size_t output_bits = 512);

      size_t hash_block_size() const override { return 128; }

      size_t output_length() const override { return m_output_bits / 8; }

      size_t key_size() const { return m_key_size; }

      Key_Length_Specification key_spec() const override;

      std::unique_ptr<HashFunction> new_object() const override;
      std::string name() const override;
      void clear() override;
      bool has_keying_material() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

   protected:
      friend class BLAKE2bMAC;

      void key_schedule(std::span<const uint8_t> key) override;

      void add_data(std::span<const uint8_t> input) override;
      void final_result(std::span<uint8_t> out) override;

   private:
      void state_init();
      void compress(const uint8_t* data, size_t blocks, uint64_t increment);

      const size_t m_output_bits;

      AlignmentBuffer<uint8_t, BLAKE2B_BLOCKBYTES, AlignmentBufferFinalBlock::must_be_deferred> m_buffer;

      secure_vector<uint64_t> m_H;
      uint64_t m_T[2];
      uint64_t m_F;

      size_t m_key_size;
      secure_vector<uint8_t> m_padded_key_buffer;
};

}  // namespace Botan

namespace Botan {

/**
 * @brief Helper class to ease in-place marshalling of concatenated fixed-length
 *        values.
 *
 * The size of the final buffer must be known from the start, reallocations are
 * not performed.
 */
class BufferStuffer final {
   public:
      constexpr explicit BufferStuffer(std::span<uint8_t> buffer) : m_buffer(buffer) {}

      /**
       * @returns a span for the next @p bytes bytes in the concatenated buffer.
       *          Checks that the buffer is not exceeded.
       */
      constexpr std::span<uint8_t> next(size_t bytes) {
         BOTAN_STATE_CHECK(m_buffer.size() >= bytes);

         auto result = m_buffer.first(bytes);
         m_buffer = m_buffer.subspan(bytes);
         return result;
      }

      template <size_t bytes>
      constexpr std::span<uint8_t, bytes> next() {
         BOTAN_STATE_CHECK(m_buffer.size() >= bytes);

         auto result = m_buffer.first<bytes>();
         m_buffer = m_buffer.subspan(bytes);
         return result;
      }

      template <concepts::contiguous_strong_type StrongT>
      StrongSpan<StrongT> next(size_t bytes) {
         return StrongSpan<StrongT>(next(bytes));
      }

      /**
       * @returns a reference to the next single byte in the buffer
       */
      constexpr uint8_t& next_byte() { return next(1)[0]; }

      constexpr void append(std::span<const uint8_t> buffer) {
         auto sink = next(buffer.size());
         std::copy(buffer.begin(), buffer.end(), sink.begin());
      }

      constexpr void append(uint8_t b, size_t repeat = 1) {
         auto sink = next(repeat);
         std::fill(sink.begin(), sink.end(), b);
      }

      constexpr bool full() const { return m_buffer.empty(); }

      constexpr size_t remaining_capacity() const { return m_buffer.size(); }

   private:
      std::span<uint8_t> m_buffer;
};

}  // namespace Botan

namespace Botan {

/**
* Struct representing a particular date and time
*/
class BOTAN_TEST_API calendar_point final {
   public:
      /** The year, less than or equal to 9999 */
      uint32_t year() const { return m_year; }

      /** The month, 1 through 12 for Jan to Dec */
      uint32_t month() const { return m_month; }

      /** The day of the month, 1 through 31 */
      uint32_t day() const { return m_day; }

      /** Hour in 24-hour form, 0 to 23 */
      uint32_t hour() const { return m_hour; }

      /** Minutes in the hour, 0 to 59 */
      uint32_t minutes() const { return m_minutes; }

      /** Seconds in the minute, 0 to 59 */
      uint32_t seconds() const { return m_seconds; }

      /**
      * Initialize a calendar_point
      * @param y the year
      * @param mon the month
      * @param d the day
      * @param h the hour
      * @param min the minute
      * @param sec the second
      */
      calendar_point(uint32_t y, uint32_t mon, uint32_t d, uint32_t h, uint32_t min, uint32_t sec);

      /**
      * Convert a time_point to a calendar_point
      * @param time_point a time point from the system clock
      */
      explicit calendar_point(const std::chrono::system_clock::time_point& time_point);

      /**
      * Return seconds since epoch
      *
      * This is negative for dates before 1970
      */
      int64_t seconds_since_epoch() const;

      /**
      * Returns an STL timepoint object
      *
      * Note this throws an exception if the time is not representable
      * in the system time_t
      */
      std::chrono::system_clock::time_point to_std_timepoint() const;

   private:
      uint16_t m_year;
      uint8_t m_month;
      uint8_t m_day;
      uint8_t m_hour;
      uint8_t m_minutes;
      uint8_t m_seconds;
};

}  // namespace Botan

namespace Botan {

/**
* DJB's ChaCha (https://cr.yp.to/chacha.html)
*/
class ChaCha final : public StreamCipher {
   public:
      /**
      * @param rounds number of rounds
      * @note Currently only 8, 12 or 20 rounds are supported, all others
      * will throw an exception
      */
      explicit ChaCha(size_t rounds = 20);

      std::string provider() const override;

      /*
      * ChaCha accepts 0, 8, 12 or 24 byte IVs.
      * The default IV is a 8 zero bytes.
      * An IV of length 0 is treated the same as the default zero IV.
      * An IV of length 24 selects XChaCha mode
      */
      bool valid_iv_length(size_t iv_len) const override;

      size_t default_iv_length() const override;

      Key_Length_Specification key_spec() const override;

      void clear() override;

      std::unique_ptr<StreamCipher> new_object() const override;

      std::string name() const override;

      void seek(uint64_t offset) override;

      bool supports_seek() const override { return true; }

      std::optional<uint64_t> remaining_keystream_bytes() const override;

      bool has_keying_material() const override;

      size_t buffer_size() const override;

   private:
      void key_schedule(std::span<const uint8_t> key) override;

      void cipher_bytes(const uint8_t in[], uint8_t out[], size_t length) override;

      void generate_keystream(uint8_t out[], size_t len) override;

      void set_iv_bytes(const uint8_t iv[], size_t iv_len) override;

      void initialize_state();

      static size_t parallelism();

      static void chacha(uint8_t output[], size_t output_blocks, uint32_t state[16], size_t rounds);

#if defined(BOTAN_HAS_CHACHA_SIMD32)
      static void chacha_simd32_x4(uint8_t output[64 * 4], uint32_t state[16], size_t rounds);
#endif

#if defined(BOTAN_HAS_CHACHA_AVX2)
      static void chacha_avx2_x8(uint8_t output[64 * 8], uint32_t state[16], size_t rounds);
#endif

#if defined(BOTAN_HAS_CHACHA_AVX512)
      static void chacha_avx512_x16(uint8_t output[64 * 16], uint32_t state[16], size_t rounds);
#endif

      size_t m_rounds;
      secure_vector<uint32_t> m_key;
      secure_vector<uint32_t> m_state;
      secure_vector<uint8_t> m_buffer;
      size_t m_position = 0;
      size_t m_iv_length = 0;
      uint32_t m_state13_post_iv = 0;
      // Valid only when m_iv_length == 12: bytes the user can still
      // generate before the 32-bit counter would wrap into the nonce.
      uint64_t m_bytes_remaining = 0;
};

}  // namespace Botan


namespace Botan {

/**
* Base class
* See draft-irtf-cfrg-chacha20-poly1305-03 for specification
* If a nonce of 64 bits is used the older version described in
* draft-agl-tls-chacha20poly1305-04 is used instead.
* If a nonce of 192 bits is used, XChaCha20Poly1305 is selected.
*/
class ChaCha20Poly1305_Mode : public AEAD_Mode {
   public:
      void set_associated_data_n(size_t idx, std::span<const uint8_t> ad) final;

      bool associated_data_requires_key() const override { return false; }

      std::string name() const override { return "ChaCha20Poly1305"; }

      size_t update_granularity() const override;

      size_t ideal_granularity() const override;

      Key_Length_Specification key_spec() const override { return Key_Length_Specification(32); }

      bool valid_nonce_length(size_t n) const override;

      size_t tag_size() const override { return 16; }

      void clear() override;

      void reset() override;

      bool has_keying_material() const final;

   protected:
      std::unique_ptr<StreamCipher> m_chacha;                 // NOLINT(*non-private-member-variable*)
      std::unique_ptr<MessageAuthenticationCode> m_poly1305;  // NOLINT(*non-private-member-variable*)

      ChaCha20Poly1305_Mode();

      secure_vector<uint8_t> m_ad;  // NOLINT(*non-private-member-variable*)
      size_t m_nonce_len = 0;       // NOLINT(*non-private-member-variable*)
      uint64_t m_ctext_len = 0;     // NOLINT(*non-private-member-variable*)

      bool cfrg_version() const { return m_nonce_len == 12 || m_nonce_len == 24; }

      void update_len(uint64_t len);

   private:
      void start_msg(const uint8_t nonce[], size_t nonce_len) override;

      void key_schedule(std::span<const uint8_t> key) override;
};

/**
* ChaCha20Poly1305 Encryption
*/
class ChaCha20Poly1305_Encryption final : public ChaCha20Poly1305_Mode {
   public:
      size_t output_length(size_t input_length) const override;

      size_t minimum_final_size() const override { return 0; }

   private:
      size_t process_msg(uint8_t buf[], size_t size) override;
      void finish_msg(secure_vector<uint8_t>& final_block, size_t offset = 0) override;
};

/**
* ChaCha20Poly1305 Decryption
*/
class ChaCha20Poly1305_Decryption final : public ChaCha20Poly1305_Mode {
   public:
      size_t output_length(size_t input_length) const override;

      size_t minimum_final_size() const override { return tag_size(); }

   private:
      size_t process_msg(uint8_t buf[], size_t size) override;
      void finish_msg(secure_vector<uint8_t>& final_block, size_t offset = 0) override;
};

}  // namespace Botan

namespace Botan {

/**
* Convert a sequence of UCS-2 (big endian) characters to a UTF-8 string
* This is used for ASN.1 BMPString type
* @param ucs2 the sequence of UCS-2 characters, length must be a multiple of 2
*/
BOTAN_TEST_API std::string ucs2_to_utf8(std::span<const uint8_t> ucs2);

/**
 * Convert a UTF-8 string to a sequence of UCS-2 (big endian) characters
 * This is used for ASN.1 BMPString type
 * @param utf8 the UTF-8 string
 * @return a vector of bytes containing the UCS-2 (big endian) encoding
 * @throws Decoding_Error if the input is not valid UTF-8 (including overlong encodings,
 *         surrogate code points, or values outside Unicode), or if a code point exceeds
 *         U+FFFF and cannot be represented in UCS-2
 */
BOTAN_TEST_API std::vector<uint8_t> utf8_to_ucs2(std::string_view utf8);

/**
* Convert a sequence of UCS-4 (big endian) characters to a UTF-8 string
* This is used for ASN.1 UniversalString type
* @param ucs4 the sequence of UCS-4 characters, length must be a multiple of 4
*/
BOTAN_TEST_API std::string ucs4_to_utf8(std::span<const uint8_t> ucs4);

/**
 * Convert a UTF-8 string to a sequence of UCS-4 (big endian) characters
 * This is used for ASN.1 UniversalString type
 * @param utf8 the UTF-8 string
 * @return a vector of bytes containing the UCS-4 (big endian) encoding
 * @throws Decoding_Error if the input is not valid UTF-8 (including overlong encodings,
 *         surrogate code points, or values outside the Unicode scalar value range U+0000..U+10FFFF)
 */
BOTAN_TEST_API std::vector<uint8_t> utf8_to_ucs4(std::string_view utf8);

BOTAN_TEST_API std::string latin1_to_utf8(std::span<const uint8_t> latin1);

/**
* Return true if this string seems to contain a valid sequence of UTF-8
*/
bool is_valid_utf8(std::string_view str);

/**
* Return true if c is a control character (0x00..0x1F) or DEL (0x7F)
*/
BOTAN_TEST_API bool is_ascii_control_char(char c);

/**
* Return true if the Unicode code point cp is a control character: a C0 control
* (U+0000..U+001F), DEL (U+007F), or a C1 control (U+0080..U+009F)
*/
BOTAN_TEST_API bool is_unicode_control_char(uint32_t cp);

/**
* Map the low four bits of b to an uppercase hex digit ('0'..'9','A'..'F')
*/
inline constexpr char nibble_to_hex(uint8_t b) {
   const uint8_t n = b & 0x0F;
   return static_cast<char>(n < 10 ? '0' + n : 'A' + (n - 10));
}

/**
* Decode the UTF-8 code point beginning at utf8[pos], advancing pos past it
* @throws Decoding_Error if the bytes at pos are not a valid UTF-8 sequence
*/
uint32_t next_utf8_codepoint(std::string_view utf8, size_t& pos);

/**
* Return a copy of utf8 with control characters escaped for safe display
*
* C0 controls (0x00..0x1F), DEL (0x7F), and C1 controls (U+0080..U+009F) are
* each replaced by a "\xHH" escape per byte; all other code points, including
* printable non-ASCII, are passed through unchanged. Any byte that is not part
* of a valid UTF-8 sequence is escaped individually.
*/
BOTAN_TEST_API std::string escape_control_chars(std::string_view utf8);

/**
* Return a string containing 'c', quoted and possibly escaped
*
* This is used when creating an error message noting an invalid character
* in some codec (for example during hex decoding)
*
* Tab, newline, and carriage return are escaped as "\t", "\n", and "\r".
* Any other control character (or DEL), and any byte above 0x7F, is escaped
* as "\xHH" where HH is the hex code.
*/
std::string format_char_for_display(char c);

/**
* Character classifier
*/
class CharacterValidityTable final {
   public:
      static constexpr CharacterValidityTable alpha_numeric_plus(std::string_view extras) {
         TableStorage tbl{};

         set_tbl_range(tbl, "0123456789");
         set_tbl_range(tbl, "abcdefghijklmnopqrstuvwxyz");
         set_tbl_range(tbl, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
         set_tbl_range(tbl, extras);

         return CharacterValidityTable(tbl);
      }

      constexpr bool operator()(char c) const {
         const uint8_t uc = static_cast<uint8_t>(c);
         return ((m_tbl[uc / 32] >> (uc % 32)) & 1) != 0;
      }

      constexpr CharacterValidityTable invert() const {
         TableStorage inverted = m_tbl;
         for(auto& v : inverted) {
            v = ~v;
         }
         return CharacterValidityTable(inverted);
      }

   private:
      using TableStorage = std::array<uint32_t, 8>;  // 256 bits of storage

      static constexpr void set_tbl_range(TableStorage& tbl, std::string_view valid_chars) {
         for(const char c : valid_chars) {
            const uint8_t uc = static_cast<uint8_t>(c);
            tbl[uc / 32] |= (uint32_t{1} << (uc % 32));
         }
      }

      explicit constexpr CharacterValidityTable(TableStorage tbl) : m_tbl(tbl) {}

      TableStorage m_tbl;
};

}  // namespace Botan

namespace Botan {

/**
* Perform encoding using the base provided
* @param base object giving access to the encodings specifications
* @param output an array of at least base.encode_max_output bytes
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
template <class Base>
size_t base_encode(const Base& base,
                   char output[],
                   const uint8_t input[],
                   size_t input_length,
                   size_t& input_consumed,
                   bool final_inputs) {
   input_consumed = 0;

   // TODO(Botan4) Check if we can use just base. or Base:: here instead
   constexpr size_t encoding_bytes_in = std::remove_reference_t<Base>::encoding_bytes_in();
   constexpr size_t encoding_bytes_out = std::remove_reference_t<Base>::encoding_bytes_out();

   size_t input_remaining = input_length;
   size_t output_produced = 0;

   while(input_remaining >= encoding_bytes_in) {
      base.encode(output + output_produced, input + input_consumed);

      input_consumed += encoding_bytes_in;
      output_produced += encoding_bytes_out;
      input_remaining -= encoding_bytes_in;
   }

   if(final_inputs && input_remaining) {
      std::array<uint8_t, encoding_bytes_in> remainder{};
      for(size_t i = 0; i != input_remaining; ++i) {
         remainder[i] = input[input_consumed + i];
      }

      base.encode(output + output_produced, remainder.data());

      const size_t bits_consumed = base.bits_consumed();
      const size_t remaining_bits_before_padding = base.remaining_bits_before_padding();

      size_t empty_bits = 8 * (encoding_bytes_in - input_remaining);
      size_t index = output_produced + encoding_bytes_out - 1;
      while(empty_bits >= remaining_bits_before_padding) {
         output[index--] = '=';
         empty_bits -= bits_consumed;
      }

      input_consumed += input_remaining;
      output_produced += encoding_bytes_out;
   }

   return output_produced;
}

template <typename Base>
std::string base_encode_to_string(const Base& base, const uint8_t input[], size_t input_length) {
   const size_t output_length = base.encode_max_output(input_length);
   std::string output(output_length, 0);

   size_t consumed = 0;
   size_t produced = 0;

   if(output_length > 0) {
      produced = base_encode(base, &output.front(), input, input_length, consumed, true);
   }

   BOTAN_ASSERT_EQUAL(consumed, input_length, "Consumed the entire input");
   BOTAN_ASSERT_EQUAL(produced, output.size(), "Produced expected size");

   return output;
}

/**
* Perform decoding using the base provided
* @param base object giving access to the encodings specifications
* @param output an array of at least Base::decode_max_output bytes
* @param input some base input
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
template <typename Base>
size_t base_decode(const Base& base,
                   uint8_t output[],
                   const char input[],
                   size_t input_length,
                   size_t& input_consumed,
                   bool final_inputs,
                   bool ignore_ws = true) {
   // TODO(Botan4) Check if we can use just base. or Base:: here instead
   constexpr size_t decoding_bytes_in = std::remove_reference_t<Base>::decoding_bytes_in();
   constexpr size_t decoding_bytes_out = std::remove_reference_t<Base>::decoding_bytes_out();

   input_consumed = 0;

   uint8_t* out_ptr = output;
   std::array<uint8_t, decoding_bytes_in> decode_buf{};
   size_t decode_buf_pos = 0;
   size_t final_truncate = 0;
   bool seen_padding = false;

   clear_mem(output, base.decode_max_output(input_length));

   for(size_t i = 0; i != input_length; ++i) {
      const uint8_t bin = base.lookup_binary_value(input[i]);

      // This call might throw Invalid_Argument
      if(base.check_bad_char(bin, input[i], ignore_ws)) {
         // Padding may only appear at the end, so a data symbol must never
         // follow one (0x81 marks a padding character)
         if(seen_padding) {
            throw Invalid_Argument(base.name() + " decoding failed, data follows padding");
         }
         decode_buf[decode_buf_pos] = bin;
         ++decode_buf_pos;
      } else if(bin == 0x81) {
         seen_padding = true;
      }

      /*
      * If we're at the end of the input, pad with 0s and truncate
      */
      if(final_inputs && (i == input_length - 1)) {
         if(decode_buf_pos) {
            const size_t bits_per_symbol = base.bits_consumed();
            const size_t pad_bits = (decode_buf_pos * bits_per_symbol) % 8;

            // A trailing symbol contributing only pad bits cannot occur in a
            // valid encoding; RFC 4648 4 and 6 enumerate the reachable cases
            if(pad_bits >= bits_per_symbol) {
               throw Invalid_Argument(base.name() + " decoding failed, invalid length");
            }

            // RFC 4648 3.5: "decoders MAY chose to reject an encoding if the
            // pad bits have not been set to zero"
            const uint8_t pad_mask = static_cast<uint8_t>((1U << pad_bits) - 1);
            if(decode_buf[decode_buf_pos - 1] & pad_mask) {
               throw Invalid_Argument(base.name() + " decoding failed, nonzero padding bits");
            }

            for(size_t j = decode_buf_pos; j < decoding_bytes_in; ++j) {
               decode_buf[j] = 0;
            }

            final_truncate = decoding_bytes_in - decode_buf_pos;
            decode_buf_pos = decoding_bytes_in;
         }
      }

      if(decode_buf_pos == decoding_bytes_in) {
         base.decode(out_ptr, decode_buf.data());

         out_ptr += decoding_bytes_out;
         decode_buf_pos = 0;
         input_consumed = i + 1;
      }
   }

   while(input_consumed < input_length && base.lookup_binary_value(input[input_consumed]) == 0x80) {
      ++input_consumed;
   }

   const size_t written = (out_ptr - output) - base.bytes_to_remove(final_truncate);

   return written;
}

template <typename Base>
size_t base_decode_full(const Base& base, uint8_t output[], const char input[], size_t input_length, bool ignore_ws) {
   size_t consumed = 0;
   const size_t written = base_decode(base, output, input, input_length, consumed, true, ignore_ws);

   if(consumed != input_length) {
      throw Invalid_Argument(base.name() + " decoding failed, input did not have full bytes");
   }

   return written;
}

template <typename Vector, typename Base>
Vector base_decode_to_vec(const Base& base, const char input[], size_t input_length, bool ignore_ws) {
   const size_t output_length = base.decode_max_output(input_length);
   Vector bin(output_length);

   const size_t written = base_decode_full(base, bin.data(), input, input_length, ignore_ws);

   bin.resize(written);
   return bin;
}

}  // namespace Botan

namespace Botan {

namespace detail {

/**
 * Helper function that performs range size-checks as required given the
 * selected output and input range types. If all lengths are known at compile
 * time, this check will be performed at compile time as well. It will then
 * instantiate an output range and concatenate the input ranges' contents.
 */
template <ranges::spanable_range OutR, ranges::spanable_range... Rs>
constexpr OutR concatenate(Rs&&... ranges)
   requires(concepts::reservable_container<OutR> || ranges::statically_spanable_range<OutR>)
{
   OutR result{};

   // Prepare and validate the output range and construct a lambda that does the
   // actual filling of the result buffer.
   // (if no input ranges are given, GCC claims that fill_fn is unused)
   [[maybe_unused]] auto fill_fn = [&] {
      if constexpr(concepts::reservable_container<OutR>) {
         // dynamically allocate the correct result byte length
         const size_t total_size = (ranges.size() + ... + 0);
         result.reserve(total_size);

         // fill the result buffer using a back-inserter
         return [&result](auto&& range) {
            std::copy(
               std::ranges::begin(range), std::ranges::end(range), std::back_inserter(unwrap_strong_type(result)));
         };
      } else {
         if constexpr((ranges::statically_spanable_range<Rs> && ... && true)) {
            // all input ranges have a static extent, so check the total size at compile time
            // (work around an issue in MSVC that warns `total_size` is unused)
            [[maybe_unused]] constexpr size_t total_size = (decltype(std::span{ranges})::extent + ... + 0);
            static_assert(result.size() == total_size, "size of result buffer does not match the sum of input buffers");
         } else {
            // at least one input range has a dynamic extent, so check the total size at runtime
            const size_t total_size = (ranges.size() + ... + 0);
            BOTAN_ARG_CHECK(result.size() == total_size,
                            "result buffer has static extent that does not match the sum of input buffers");
         }

         // fill the result buffer and hold the current output-iterator position
         return [itr = std::ranges::begin(result)](auto&& range) mutable {
            std::copy(std::ranges::begin(range), std::ranges::end(range), itr);
            std::advance(itr, std::ranges::size(range));
         };
      }
   }();

   // perform the actual concatenation
   (fill_fn(std::forward<Rs>(ranges)), ...);

   return result;
}

}  // namespace detail

/**
 * Concatenate an arbitrary number of buffers. Performs range-checks as needed.
 *
 * The output type can be auto-detected based on the input ranges, or explicitly
 * specified by the caller. If all input ranges have a static extent, the total
 * size is calculated at compile time and a statically sized std::array<> is used.
 * Otherwise this tries to use the type of the first input range as output type.
 *
 * Alternatively, the output container type can be specified explicitly.
 */
template <typename OutR = detail::AutoDetect, ranges::spanable_range... Rs>
constexpr auto concat(Rs&&... ranges)
   requires(all_same_v<std::ranges::range_value_t<Rs>...>)
{
   if constexpr(std::same_as<detail::AutoDetect, OutR>) {
      // Try to auto-detect a reasonable output type given the input ranges
      static_assert(sizeof...(Rs) > 0, "Cannot auto-detect the output type if not a single input range is provided.");
      using candidate_result_t = std::remove_cvref_t<std::tuple_element_t<0, std::tuple<Rs...>>>;
      using result_range_value_t = std::remove_cvref_t<std::ranges::range_value_t<candidate_result_t>>;

      if constexpr((ranges::statically_spanable_range<Rs> && ...)) {
         // If all input ranges have a static extent, we can calculate the total size at compile time
         // and therefore can use a statically sized output container. This is constexpr.
         constexpr size_t total_size = (decltype(std::span{ranges})::extent + ... + 0);
         using out_array_t = std::array<result_range_value_t, total_size>;
         return detail::concatenate<out_array_t>(std::forward<Rs>(ranges)...);
      } else {
         // If at least one input range has a dynamic extent, we must use a dynamically allocated output container.
         // We assume that the user wants to use the first input range's container type as output type.
         static_assert(
            concepts::reservable_container<candidate_result_t>,
            "First input range has static extent, but a dynamically allocated output range is required. Please explicitly specify a dynamically allocatable output type.");
         return detail::concatenate<candidate_result_t>(std::forward<Rs>(ranges)...);
      }
   } else {
      // The caller has explicitly specified the output type
      return detail::concatenate<OutR>(std::forward<Rs>(ranges)...);
   }
}

}  // namespace Botan

#if defined(BOTAN_HAS_CPUID_DETECTION)

namespace Botan {

class BOTAN_TEST_API CPUFeature final {
   public:
      enum Bit : uint32_t /* NOLINT(*-use-enum-class) */ {
         NEON = (1U << 0),
         SVE = (1U << 1),
         AES = (1U << 16),
         PMULL = (1U << 17),
         SHA1 = (1U << 18),
         SHA2 = (1U << 19),
         SHA3 = (1U << 20),
         SHA2_512 = (1U << 21),
         SM3 = (1U << 22),
         SM4 = (1U << 23),

         SIMD_4X32 = NEON,
         HW_AES = AES,
         HW_CLMUL = PMULL,
      };

      CPUFeature(Bit b) : m_bit(b) {}  // NOLINT(*-explicit-conversions)

      uint32_t as_u32() const { return static_cast<uint32_t>(m_bit); }

      std::string to_string() const;

      static std::optional<CPUFeature> from_string(std::string_view s);

   private:
      Bit m_bit;
};

}  // namespace Botan
#endif

namespace Botan {

#if !defined(BOTAN_HAS_CPUID_DETECTION)
// A no-op CPUFeature
class BOTAN_TEST_API CPUFeature final {
   public:
      enum Bit : uint32_t {};

      uint32_t as_u32() const;

      CPUFeature(Bit) {}

      static std::optional<CPUFeature> from_string(std::string_view);

      std::string to_string() const;
};
#endif

/**
* A class handling runtime CPU feature detection. It is limited to
* just the features necessary to implement CPU specific code in Botan,
* rather than being a general purpose utility.
*/
class BOTAN_TEST_API CPUID final {
   public:
      typedef CPUFeature Feature;

      /**
      * Probe the CPU and see what extensions are supported
      */
      static void initialize();

      /**
      * Return a possibly empty string containing list of known CPU
      * extensions. Each name will be separated by a space, and the ordering
      * will be arbitrary. This list only contains values that are useful to
      * Botan (for example FMA instructions are not checked).
      *
      * Example outputs "sse2 ssse3 rdtsc", "neon arm_aes", "altivec"
      */
      static std::string to_string();

      /**
      * Check if a feature is supported returning the associated string if so
      *
      * This is a helper function used to implement provider()
      */
      static std::optional<std::string> check(CPUID::Feature feat) {
         if(state().has_bit(feat.as_u32())) {
            return feat.to_string();
         } else {
            return {};
         }
      }

      /**
      * Check if a feature is supported returning the associated string if so
      *
      * This is a helper function used to implement provider()
      */
      static std::optional<std::string> check(CPUID::Feature feat1, CPUID::Feature feat2) {
         if(state().has_bit((feat1.as_u32() | feat2.as_u32()))) {
            // Typically feat2 is a secondary feature that is almost but not
            // completely implied by feat1 (ex: AVX2 + BMI2) which we have to
            // check for completeness, but don't reflect into the provider name.
            return feat1.to_string();
         } else {
            return {};
         }
      }

      /**
      * Check if a feature is supported
      */
      static bool has(CPUID::Feature feat) { return state().has_bit(feat.as_u32()); }

      /**
      * Check if two features are both supported
      */
      static bool has(CPUID::Feature feat1, CPUID::Feature feat2) {
         return state().has_bit(feat1.as_u32() | feat2.as_u32());
      }

      /*
      * Clear a CPUID bit
      * Call CPUID::initialize to reset
      *
      * This is only exposed for testing and should never be called within the library
      */
      static void clear_cpuid_bit(CPUID::Feature bit) { state().clear_cpuid_bit(bit.as_u32()); }

      static std::optional<CPUID::Feature> bit_from_string(std::string_view tok);

      /**
      * A common helper for the various CPUID implementations
      */
      template <typename T>
      static inline uint32_t if_set(uint64_t cpuid, T flag, CPUID::Feature bit, uint32_t allowed) {
         const uint64_t flag64 = static_cast<uint64_t>(flag);
         if((cpuid & flag64) == flag64) {
            return (bit.as_u32() & allowed);
         } else {
            return 0;
         }
      }

   private:
      static inline bool is_set(uint32_t allowed, CPUID::Feature bit) {
         const uint32_t feat_bit = bit.as_u32();
         return ((allowed & feat_bit) == feat_bit);
      }

      struct CPUID_Data {
         public:
            CPUID_Data();

            CPUID_Data(const CPUID_Data& other) = default;
            CPUID_Data(CPUID_Data&& other) = default;
            CPUID_Data& operator=(const CPUID_Data& other) = default;
            CPUID_Data& operator=(CPUID_Data&& other) = default;
            ~CPUID_Data() = default;

            void clear_cpuid_bit(uint32_t bit) { m_processor_features &= ~bit; }

            bool has_bit(uint32_t bit) const { return (m_processor_features & bit) == bit; }

            uint32_t bitset() const { return m_processor_features; }

         private:
#if defined(BOTAN_HAS_CPUID_DETECTION)
            static uint32_t detect_cpu_features(uint32_t allowed_bits);
#endif

            uint32_t m_processor_features;
      };

      static CPUID_Data& state() {
         static CPUID::CPUID_Data g_cpuid;
         return g_cpuid;
      }
};

}  // namespace Botan

namespace Botan {

/**
 * @brief Helper class to create a RAII-style cleanup callback
 *
 * Ensures that the cleanup callback given in the object's constructor is called
 * when the object is destroyed. Use this to ensure some cleanup code runs when
 * leaving the current scope.
 */
template <std::invocable FunT>
class scoped_cleanup final {
   public:
      explicit scoped_cleanup(FunT cleanup) : m_cleanup(std::move(cleanup)) {}

      scoped_cleanup(const scoped_cleanup&) = delete;
      scoped_cleanup& operator=(const scoped_cleanup&) = delete;
      scoped_cleanup& operator=(scoped_cleanup&& other) = delete;

      scoped_cleanup(scoped_cleanup&& other) noexcept : m_cleanup(std::move(other.m_cleanup)) { other.disengage(); }

      ~scoped_cleanup() {
         if(m_cleanup.has_value()) {
            (*m_cleanup)();  // NOLINT(bugprone-exception-escape) clang-tidy bug
         }
      }

      /**
       * Disengage the cleanup callback, i.e., prevent it from being called
       */
      void disengage() noexcept { m_cleanup.reset(); }

   private:
      std::optional<FunT> m_cleanup;
};

}  // namespace Botan


#if defined(BOTAN_HAS_VALGRIND)
   #include <valgrind/memcheck.h>
#endif

namespace Botan::CT {

/// @name Constant Time Check Annotation Helpers
/// @{

/**
* Use valgrind to mark the contents of memory as being undefined.
* Valgrind will accept operations which manipulate undefined values,
* but will warn if an undefined value is used to decided a conditional
* jump or a load/store address. So if we poison all of our inputs we
* can confirm that the operations in question are truly const time
* when compiled by whatever compiler is in use.
*
* Even better, the VALGRIND_MAKE_MEM_* macros work even when the
* program is not run under valgrind (though with a few cycles of
* overhead, which is unfortunate in final binaries as these
* annotations tend to be used in fairly important loops).
*
* This approach was first used in ctgrind (https://github.com/agl/ctgrind)
* but calling the valgrind mecheck API directly works just as well and
* doesn't require a custom patched valgrind.
*/
template <typename T>
constexpr inline void poison(const T* p, size_t n) {
#if defined(BOTAN_HAS_VALGRIND)
   if(!std::is_constant_evaluated()) {
      VALGRIND_MAKE_MEM_UNDEFINED(p, n * sizeof(T));
   }
#endif

   BOTAN_UNUSED(p, n);
}

template <typename T>
constexpr inline void unpoison(const T* p, size_t n) {
#if defined(BOTAN_HAS_VALGRIND)
   if(!std::is_constant_evaluated()) {
      VALGRIND_MAKE_MEM_DEFINED(p, n * sizeof(T));
   }
#endif

   BOTAN_UNUSED(p, n);
}

/**
 * Checks whether CT::poison() and CT::unpoison() actually have an effect.
 *
 * If the build is not instrumented and/or not run using an analysis tool like
 * valgrind, the functions are no-ops and the return value is false.
 *
 * @returns true if CT::poison() and CT::unpoison() are effective
 */
inline bool poison_has_effect() {
#if defined(BOTAN_HAS_VALGRIND)
   return RUNNING_ON_VALGRIND;
#else
   return false;
#endif
}

/// @}

/// @name Constant Time Check Annotation Convenience overloads
/// @{

template <typename T>
concept custom_poisonable = requires(const T& v) { v._const_time_poison(); };
template <typename T>
concept custom_unpoisonable = requires(const T& v) { v._const_time_unpoison(); };

/**
 * Poison a single integral object
 */
template <std::integral T>
constexpr void poison(const T& p) {
   poison(&p, 1);
}

template <std::integral T>
constexpr void unpoison(const T& p) {
   unpoison(&p, 1);
}

/**
 * Poison a contiguous buffer of trivial objects (e.g. integers and such)
 */
template <ranges::spanable_range R>
   requires std::is_trivially_copyable_v<std::ranges::range_value_t<R>> && (!custom_poisonable<R>)
constexpr void poison(const R& r) {
   const std::span s{r};
   poison(s.data(), s.size());
}

template <ranges::spanable_range R>
   requires std::is_trivially_copyable_v<std::ranges::range_value_t<R>> && (!custom_unpoisonable<R>)
constexpr void unpoison(const R& r) {
   const std::span s{r};
   unpoison(s.data(), s.size());
}

/**
 * Poison a class type that provides a public `_const_time_poison()` method
 * For instance: BigInt, CT::Mask<>, FrodoMatrix, ...
 */
template <custom_poisonable T>
constexpr void poison(const T& x) {
   x._const_time_poison();
}

template <custom_unpoisonable T>
constexpr void unpoison(const T& x) {
   x._const_time_unpoison();
}

/**
 * Poison an optional object if it has a value.
 */
template <typename T>
   requires requires(const T& v) { ::Botan::CT::poison(v); }
constexpr void poison(const std::optional<T>& x) {
   if(x.has_value()) {
      poison(*x);
   }
}

template <typename T>
   requires requires(const T& v) { ::Botan::CT::unpoison(v); }
constexpr void unpoison(const std::optional<T>& x) {
   if(x.has_value()) {
      unpoison(*x);
   }
}

/// @}

/// @name Higher-level Constant Time Check Annotation Helpers
/// @{

template <typename T>
concept poisonable = requires(const T& v) { ::Botan::CT::poison(v); };
template <typename T>
concept unpoisonable = requires(const T& v) { ::Botan::CT::unpoison(v); };

/**
 * Poison a range of objects by calling `poison` on each element.
 */
template <std::ranges::range R>
   requires poisonable<std::ranges::range_value_t<R>>
constexpr void poison_range(const R& r) {
   for(const auto& v : r) {
      poison(v);
   }
}

template <std::ranges::range R>
   requires unpoisonable<std::ranges::range_value_t<R>>
constexpr void unpoison_range(const R& r) {
   for(const auto& v : r) {
      unpoison(v);
   }
}

/**
 * Poisons an arbitrary number of values in a single call.
 * Mostly syntactic sugar to save clutter (i.e. lines-of-code).
 */
template <poisonable... Ts>
   requires(sizeof...(Ts) > 0)
constexpr void poison_all(const Ts&... ts) {
   (poison(ts), ...);
}

template <unpoisonable... Ts>
   requires(sizeof...(Ts) > 0)
constexpr void unpoison_all(const Ts&... ts) {
   (unpoison(ts), ...);
}

/**
 * Poisons an arbitrary number of poisonable values, and unpoisons them when the
 * returned object runs out-of-scope
 *
 * Use this when you want to poison a value that remains valid longer than the
 * scope you are currently in. For instance, a private key structure that is a
 * member of a Signature_Operation object, that may be used for multiple
 * signatures.
 */
template <typename... Ts>
   requires(sizeof...(Ts) > 0) && (poisonable<Ts> && ...) && (unpoisonable<Ts> && ...)
[[nodiscard]] constexpr auto scoped_poison(const Ts&... xs) {
   auto scope = scoped_cleanup([&] { unpoison_all(xs...); });
   poison_all(xs...);
   return scope;
}

/**
 * Poisons an r-value @p v and forwards it as the return value.
 */
template <poisonable T>
[[nodiscard]] decltype(auto) driveby_poison(T&& v)
   requires(std::is_rvalue_reference_v<decltype(v)>)
{
   poison(v);
   return std::forward<T>(v);
}

/**
 * Unpoisons an r-value @p v and forwards it as the return value.
 */
template <unpoisonable T>
[[nodiscard]] decltype(auto) driveby_unpoison(T&& v)
   requires(std::is_rvalue_reference_v<decltype(v)>)
{
   unpoison(v);
   return std::forward<T>(v);
}

/// @}

/**
* A Choice is used for constant-time conditionals.
*
* Internally it always is either |0| (all 0 bits) or |1| (all 1 bits)
* and measures are taken to block compilers from reasoning about the
* expected value of a Choice.
*/
class Choice final {
   public:
      using underlying_type = word;

      /**
      * If v == 0 return an unset (false) Choice, otherwise a set Choice
      */
      template <typename T>
         requires std::unsigned_integral<T> && (!std::same_as<bool, T>)
      constexpr static Choice from_int(T v) {
         if constexpr(sizeof(T) <= sizeof(underlying_type)) {
            return !Choice(ct_is_zero<underlying_type>(v));
         } else {
            // Mask of T that is either |0| or |1|
            const T v_is_0 = ct_is_zero<T>(value_barrier<T>(v));

            // We want the mask to be set if v != 0 so we must check that
            // v_is_0 is itself zero.
            //
            // Also sizeof(T) may not equal sizeof(underlying_type) so we must
            // use ct_is_zero<underlying_type>. It's ok to either truncate or
            // zero extend v_is_0 to 32 bits since we know it is |0| or |1|
            // so even just the low bit is sufficient.
            return Choice(ct_is_zero<underlying_type>(static_cast<underlying_type>(v_is_0)));
         }
      }

      /**
      * Return a bitmask |1| if the choice is set, or |0| otherwise
      */
      template <typename T>
         requires std::unsigned_integral<T> && (!std::same_as<bool, T>)
      constexpr T into_bitmask() const {
         if constexpr(sizeof(T) <= sizeof(underlying_type)) {
            // The inner mask is already |0| or |1| so just truncate
            return static_cast<T>(value());
         } else {
            return ~ct_is_zero<T>(value());
         }
      }

      /**
      * Create a Choice directly from a mask value - this assumes v is either |0| or |1|
      */
      constexpr static Choice from_mask(underlying_type v) { return Choice(v); }

      constexpr static Choice yes() { return !no(); }

      constexpr static Choice no() { return Choice(0); }

      constexpr Choice operator!() const { return Choice(~value()); }

      constexpr Choice operator&&(const Choice& other) const { return Choice(value() & other.value()); }

      constexpr Choice operator||(const Choice& other) const { return Choice(value() | other.value()); }

      constexpr Choice operator!=(const Choice& other) const { return Choice(value() ^ other.value()); }

      constexpr Choice operator==(const Choice& other) const { return !(*this != other); }

      /**
      * Unsafe conversion to bool
      *
      * This conversion itself is (probably) constant time, but once the
      * choice is reduced to a simple bool, it's entirely possible for the
      * compiler to perform range analysis on the values, since there are just
      * the two. As a consequence even if the caller is not using this in an
      * obviously branchy way (`if(choice.as_bool()) ...`) a smart compiler
      * may introduce branches depending on the value.
      */
      constexpr bool as_bool() const { return m_value != 0; }

      /// Return the masked value
      constexpr underlying_type value() const { return value_barrier(m_value); }

      constexpr Choice(const Choice& other) = default;
      constexpr Choice(Choice&& other) = default;
      constexpr Choice& operator=(const Choice& other) noexcept = default;
      constexpr Choice& operator=(Choice&& other) noexcept = default;
      constexpr ~Choice() = default;

   private:
      constexpr explicit Choice(underlying_type v) : m_value(CT::value_barrier<underlying_type>(v)) {}

      underlying_type m_value;
};

/**
* A concept for a type which is conditionally assignable
*/
template <typename T>
concept ct_conditional_assignable = requires(T lhs, const T& rhs, Choice c) { lhs.conditional_assign(c, rhs); };

/**
* A Mask type used for constant-time operations. A Mask<T> always has value
* either |0| (all bits cleared) or |1| (all bits set). All operations in a Mask<T>
* are intended to compile to code which does not contain conditional jumps.
* This must be verified with tooling (eg binary disassembly or using valgrind)
* since you never know what a compiler might do.
*/
template <typename T>
class Mask final {
   public:
      static_assert(std::is_unsigned_v<T> && !std::is_same_v<bool, T>,
                    "Only unsigned integer types are supported by CT::Mask");

      Mask(const Mask<T>& other) = default;
      Mask(Mask<T>&& other) = default;
      Mask<T>& operator=(const Mask<T>& other) = default;
      Mask<T>& operator=(Mask<T>&& other) = default;
      ~Mask() = default;

      /**
      * Derive a Mask from a Mask of a larger type
      */
      template <typename U>
      constexpr explicit Mask(Mask<U> o) : m_mask(static_cast<T>(o.value())) {
         static_assert(sizeof(U) > sizeof(T), "sizes ok");
      }

      /**
      * Return a Mask<T> of |1| (all bits set)
      */
      static constexpr Mask<T> set() { return Mask<T>(static_cast<T>(~0)); }

      /**
      * Return a Mask<T> of |0| (all bits cleared)
      */
      static constexpr Mask<T> cleared() { return Mask<T>(0); }

      /**
      * Return a Mask<T> which is set if v is != 0
      */
      static constexpr Mask<T> expand(T v) { return ~Mask<T>::is_zero(value_barrier<T>(v)); }

      /**
      * Return a Mask<T> which is set if v is true
      */
      static constexpr Mask<T> expand_bool(bool v) { return Mask<T>::expand(static_cast<T>(v)); }

      /**
      * Return a Mask<T> which is set if choice is set
      */
      static constexpr Mask<T> from_choice(Choice c) {
         if constexpr(sizeof(T) <= sizeof(Choice::underlying_type)) {
            // Take advantage of the fact that Choice's mask is always
            // either |0| or |1|
            return Mask<T>(static_cast<T>(c.value()));
         } else {
            return ~Mask<T>::is_zero(c.value());
         }
      }

      /**
      * Return a Mask<T> which is set if the top bit of v is set
      */
      static constexpr Mask<T> expand_top_bit(T v) { return Mask<T>(ct_expand_top_bit<T>(v)); }

      /**
       * Return a Mask<T> which is set if the given @p bit of @p v is set.
       * @p bit must be from 0 (LSB) to (sizeof(T) * 8 - 1) (MSB).
       */
      static constexpr Mask<T> expand_bit(T v, size_t bit) {
         return CT::Mask<T>::expand_top_bit(v << (sizeof(v) * 8 - 1 - bit));
      }

      /**
      * Return a Mask<T> which is set if m is set
      */
      template <typename U>
      static constexpr Mask<T> expand(Mask<U> m) {
         static_assert(sizeof(U) < sizeof(T), "sizes ok");
         return ~Mask<T>::is_zero(m.value());
      }

      /**
      * Return a Mask<T> which is set if v is == 0 or cleared otherwise
      */
      static constexpr Mask<T> is_zero(T x) { return Mask<T>(ct_is_zero<T>(value_barrier<T>(x))); }

      /**
      * Return a Mask<T> which is set if x == y
      */
      static constexpr Mask<T> is_equal(T x, T y) {
         const T diff = value_barrier(x) ^ value_barrier(y);
         return Mask<T>::is_zero(diff);
      }

      /**
      * Return a Mask<T> which is set if x < y
      */
      static constexpr Mask<T> is_lt(T x, T y) {
         T u = x ^ ((x ^ y) | ((x - y) ^ x));
         return Mask<T>::expand_top_bit(u);
      }

      /**
      * Return a Mask<T> which is set if x > y
      */
      static constexpr Mask<T> is_gt(T x, T y) { return Mask<T>::is_lt(y, x); }

      /**
      * Return a Mask<T> which is set if x <= y
      */
      static constexpr Mask<T> is_lte(T x, T y) { return ~Mask<T>::is_gt(x, y); }

      /**
      * Return a Mask<T> which is set if x >= y
      */
      static constexpr Mask<T> is_gte(T x, T y) { return ~Mask<T>::is_lt(x, y); }

      static constexpr Mask<T> is_within_range(T v, T l, T u) {
         //return Mask<T>::is_gte(v, l) & Mask<T>::is_lte(v, u);

         const T v_lt_l = v ^ ((v ^ l) | ((v - l) ^ v));
         const T v_gt_u = u ^ ((u ^ v) | ((u - v) ^ u));
         const T either = value_barrier(v_lt_l) | value_barrier(v_gt_u);
         return ~Mask<T>::expand_top_bit(either);
      }

      static constexpr Mask<T> is_any_of(T v, std::initializer_list<T> accepted) {
         T accept = 0;

         for(auto a : accepted) {
            const T diff = a ^ v;
            const T eq_zero = value_barrier<T>(~diff & (diff - 1));
            accept |= eq_zero;
         }

         return Mask<T>::expand_top_bit(accept);
      }

      /**
      * AND-combine two masks
      */
      Mask<T>& operator&=(Mask<T> o) {
         m_mask &= o.value();
         return (*this);
      }

      /**
      * XOR-combine two masks
      */
      Mask<T>& operator^=(Mask<T> o) {
         m_mask ^= o.value();
         return (*this);
      }

      /**
      * OR-combine two masks
      */
      Mask<T>& operator|=(Mask<T> o) {
         m_mask |= o.value();
         return (*this);
      }

      /**
      * AND-combine two masks
      */
      friend Mask<T> operator&(Mask<T> x, Mask<T> y) { return Mask<T>(x.value() & y.value()); }

      /**
      * XOR-combine two masks
      */
      friend Mask<T> operator^(Mask<T> x, Mask<T> y) { return Mask<T>(x.value() ^ y.value()); }

      /**
      * OR-combine two masks
      */
      friend Mask<T> operator|(Mask<T> x, Mask<T> y) { return Mask<T>(x.value() | y.value()); }

      /**
      * Negate this mask
      */
      constexpr Mask<T> operator~() const { return Mask<T>(~value()); }

      /**
      * Return x if the mask is set, or otherwise zero
      */
      constexpr T if_set_return(T x) const { return value() & x; }

      /**
      * Return x if the mask is cleared, or otherwise zero
      */
      constexpr T if_not_set_return(T x) const { return ~value() & x; }

      /**
      * If this mask is set, return x, otherwise return y
      */
      constexpr T select(T x, T y) const { return choose(value(), x, y); }

      constexpr T select_and_unpoison(T x, T y) const {
         T r = this->select(x, y);
         CT::unpoison(r);
         return r;
      }

      /**
      * If this mask is set, return x, otherwise return y
      */
      Mask<T> select_mask(Mask<T> x, Mask<T> y) const { return Mask<T>(select(x.value(), y.value())); }

      /**
      * Conditionally set output to x or y, depending on if mask is set or
      * cleared (resp)
      */
      constexpr void select_n(T output[], const T x[], const T y[], size_t len) const {
         const T mask = value();
         for(size_t i = 0; i != len; ++i) {
            output[i] = choose(mask, x[i], y[i]);
         }
      }

      /**
      * If this mask is set, zero out buf, otherwise do nothing
      */
      constexpr void if_set_zero_out(T buf[], size_t elems) {
         for(size_t i = 0; i != elems; ++i) {
            buf[i] = this->if_not_set_return(buf[i]);
         }
      }

      /**
     * If this mask is set, swap x and y
     */
      template <typename U>
      void conditional_swap(U& x, U& y) const
         requires(sizeof(U) <= sizeof(T))
      {
         auto cnd = Mask<U>(*this);
         U t0 = cnd.select(y, x);
         U t1 = cnd.select(x, y);
         x = t0;
         y = t1;
      }

      /**
      * Return the value of the mask, unpoisoned
      */
      constexpr T unpoisoned_value() const {
         T r = value();
         CT::unpoison(r);
         return r;
      }

      /**
      * Unsafe conversion to bool
      *
      * This conversion itself is (probably) constant time, but once the
      * mask is reduced to a simple bool, it's entirely possible for the
      * compiler to perform range analysis on the values, since there are just
      * the two. As a consequence even if the caller is not using this in an
      * obviously branchy way (`if(mask.as_bool()) ...`) a smart compiler
      * may introduce branches depending on the value.
      */
      constexpr bool as_bool() const { return unpoisoned_value() != 0; }

      /**
      * Return a Choice based on this mask
      */
      constexpr CT::Choice as_choice() const {
         if constexpr(sizeof(T) >= sizeof(Choice::underlying_type)) {
            return CT::Choice::from_mask(static_cast<Choice::underlying_type>(unpoisoned_value()));
         } else {
            return CT::Choice::from_int(unpoisoned_value());
         }
      }

      /**
      * Return the underlying value of the mask
      */
      constexpr T value() const { return value_barrier<T>(m_mask); }

      constexpr void _const_time_poison() const { CT::poison(m_mask); }

      constexpr void _const_time_unpoison() const { CT::unpoison(m_mask); }

   private:
      constexpr explicit Mask(T m) : m_mask(m) {}

      T m_mask;
};

/**
* A CT::Option<T> is either a valid T, or not
*
* To maintain constant time behavior a value must always be stored.
* A CT::Choice tracks if the value is valid or not. It is not possible
* to access the inner value if the Choice is unset.
*/
template <typename T>
class Option final {
   public:
      /// Construct an Option which contains the specified value, and is set or not
      constexpr Option(T v, Choice valid) : m_has_value(valid), m_value(std::move(v)) {}

      /// Construct a set option with the provided value
      constexpr explicit Option(T v) : Option(std::move(v), Choice::yes()) {}

      /// Construct an unset option with a default inner value
      constexpr Option()
         requires std::default_initializable<T>
            : Option(T(), Choice::no()) {}

      /// Return true if this Option contains a value
      constexpr Choice has_value() const { return m_has_value; }

      /**
      * Apply a function to the inner value and return a new Option
      * which contains that value. This is constant time only if @p f is.
      *
      * @note The function will always be called, even if the Option is None. It
      *       must be prepared to handle any possible state of T.
      */
      template <std::invocable<const T&> F>
      constexpr auto transform(F f) const -> Option<std::remove_cvref_t<std::invoke_result_t<F, const T&>>> {
         return {f(m_value), m_has_value};
      }

      /// Either returns the value or throws an exception
      constexpr const T& value() const {
         BOTAN_STATE_CHECK(m_has_value.as_bool());
         return m_value;
      }

      /// Returns either the inner value or the alternative, in constant time
      ///
      /// This variant is used for types which explicitly define a function
      /// conditional_assign which takes a CT::Choice as the conditional.
      constexpr T value_or(T other) const
         requires ct_conditional_assignable<T>
      {
         other.conditional_assign(m_has_value, m_value);
         return other;
      }

      /// Returns either the inner value or the alternative, in constant time
      ///
      /// This variant is used for integer types where CT::Mask can perform
      /// a constant time selection
      constexpr T value_or(T other) const
         requires std::unsigned_integral<T>
      {
         auto mask = CT::Mask<T>::from_choice(m_has_value);
         return mask.select(m_value, other);
      }

      /// Convert this Option into a std::optional
      ///
      /// This is not constant time, leaking if the Option had a
      /// value or not
      constexpr std::optional<T> as_optional_vartime() const {
         if(m_has_value.as_bool()) {
            return {m_value};
         } else {
            return {};
         }
      }

      /// Return a new CT::Option that is set if @p also is set as well
      constexpr CT::Option<T> operator&&(CT::Choice also) { return CT::Option<T>(m_value, m_has_value && also); }

   private:
      Choice m_has_value;
      T m_value;
};

/**
* Conditional memory copy (constant time)
*
* If mask is set, then sets dest to if_set, otherwise sets dest to if_unset
*/
template <typename T>
constexpr inline Mask<T> conditional_copy_mem(Mask<T> mask, T* dest, const T* if_set, const T* if_unset, size_t elems) {
   mask.select_n(dest, if_set, if_unset, elems);
   return mask;
}

template <typename T>
constexpr inline Mask<T> conditional_copy_mem(T cnd, T* dest, const T* if_set, const T* if_unset, size_t elems) {
   const auto mask = CT::Mask<T>::expand(cnd);
   return CT::conditional_copy_mem(mask, dest, if_set, if_unset, elems);
}

/**
* Conditional memory assignment (constant time)
*
* If mask is set overwrites dest with src
*/
template <typename T>
constexpr inline Mask<T> conditional_assign_mem(T cnd, T* dest, const T* src, size_t elems) {
   const auto mask = CT::Mask<T>::expand(cnd);
   mask.select_n(dest, src, dest, elems);
   return mask;
}

/**
* Conditional memory assignment (constant time)
*
* If mask is set overwrites dest with src
*/
template <typename T>
constexpr inline Mask<T> conditional_assign_mem(Choice cnd, T* dest, const T* src, size_t elems) {
   const auto mask = CT::Mask<T>::from_choice(cnd);
   mask.select_n(dest, src, dest, elems);
   return mask;
}

template <typename T>
constexpr inline void conditional_swap(bool cnd, T& x, T& y) {
   const auto swap = CT::Mask<T>::expand(cnd);
   swap.conditional_swap(x, y);
}

template <typename T>
constexpr inline void conditional_swap_ptr(bool cnd, T& x, T& y) {
   uintptr_t xp = reinterpret_cast<uintptr_t>(x);
   uintptr_t yp = reinterpret_cast<uintptr_t>(y);

   conditional_swap<uintptr_t>(cnd, xp, yp);

   x = reinterpret_cast<T>(xp);  // NOLINT(*-no-int-to-ptr)
   y = reinterpret_cast<T>(yp);  // NOLINT(*-no-int-to-ptr)
}

template <typename T>
constexpr inline CT::Mask<T> all_zeros(const T elem[], size_t len) {
   T sum = 0;
   for(size_t i = 0; i != len; ++i) {
      sum |= elem[i];
   }
   return CT::Mask<T>::is_zero(sum);
}

/**
* Compare two arrays of equal size and return a Mask indicating if
* they are equal or not. The mask is set if they are identical.
*/
template <typename T>
constexpr inline CT::Mask<T> is_equal(const T x[], const T y[], size_t len) {
   if(std::is_constant_evaluated()) {
      T difference = 0;

      for(size_t i = 0; i != len; ++i) {
         difference = difference | (x[i] ^ y[i]);
      }

      return CT::Mask<T>::is_zero(difference);
   } else {
      volatile T difference = 0;

      for(size_t i = 0; i != len; ++i) {
         difference = difference | (x[i] ^ y[i]);
      }

      return CT::Mask<T>::is_zero(difference);
   }
}

/**
* Compare two spans and return a Mask which is set iff they were identical.
*
* If the spans are of different length then the function returns early without
* looking at either span
*/
template <typename T>
constexpr inline CT::Mask<T> is_equal(std::span<const T> x, std::span<const T> y) {
   if(x.size() != y.size()) {
      return CT::Mask<T>::cleared();
   }

   return is_equal(x.data(), y.data(), x.size());
}

/**
* Compare two arrays of equal size and return a Mask indicating if
* they are equal or not. The mask is set if they differ.
*/
template <typename T>
constexpr inline CT::Mask<T> is_not_equal(const T x[], const T y[], size_t len) {
   return ~CT::is_equal(x, y, len);
}

/**
* Constant time conditional copy out with offset
*
* If accept is set and offset <= input_length, sets output[0..] to
* input[offset:input_length] and returns input_length - offset. The
* remaining bytes of output are zeroized.
*
* Otherwise, output is zeroized, and returns an empty Ct::Option
*
* The input and output spans may not overlap, and output must be at
* least as large as input.
*
* This function attempts to avoid leaking the following to side channels
*  - if accept was set or not
*  - the value of offset
*  - the value of input
*
* This function leaks the length of the input
*/
BOTAN_TEST_API
CT::Option<size_t> copy_output(CT::Choice accept,
                               std::span<uint8_t> output,
                               std::span<const uint8_t> input,
                               size_t offset);

size_t count_leading_zero_bytes(std::span<const uint8_t> input);

secure_vector<uint8_t> strip_leading_zeros(std::span<const uint8_t> input);

}  // namespace Botan::CT

namespace Botan {

/**
* CTR-BE (Counter mode, big-endian)
*/
class CTR_BE final : public StreamCipher {
   public:
      size_t default_iv_length() const override;

      bool valid_iv_length(size_t iv_len) const override;

      Key_Length_Specification key_spec() const override;

      std::string name() const override;

      std::unique_ptr<StreamCipher> new_object() const override;

      void clear() override;

      bool has_keying_material() const override;

      size_t buffer_size() const override;

      /**
      * @param cipher the block cipher to use
      */
      explicit CTR_BE(std::unique_ptr<BlockCipher> cipher);

      CTR_BE(std::unique_ptr<BlockCipher> cipher, size_t ctr_size);

      void seek(uint64_t offset) override;

      bool supports_seek() const override { return true; }

      std::optional<uint64_t> remaining_keystream_bytes() const override;

   private:
      void key_schedule(std::span<const uint8_t> key) override;
      void cipher_bytes(const uint8_t in[], uint8_t out[], size_t length) override;
      void generate_keystream(uint8_t out[], size_t length) override;
      void set_iv_bytes(const uint8_t iv[], size_t iv_len) override;
      void add_counter(uint64_t counter);

#if defined(BOTAN_HAS_CTR_BE_AVX2)
      size_t ctr_proc_bs16_ctr4_avx2(const uint8_t in[], uint8_t out[], size_t length);
#endif

#if defined(BOTAN_HAS_CTR_BE_SIMD32)
      size_t ctr_proc_bs16_ctr4_simd32(const uint8_t in[], uint8_t out[], size_t length);
#endif

      std::unique_ptr<BlockCipher> m_cipher;

      const size_t m_block_size;
      const size_t m_ctr_size;
      const size_t m_ctr_blocks;

      secure_vector<uint8_t> m_counter, m_pad;
      std::vector<uint8_t> m_iv;
      size_t m_pad_pos;
      // Valid only when m_ctr_size < 8: bytes the user can still
      // generate before the narrow counter would wrap.
      uint64_t m_bytes_remaining = 0;
};

}  // namespace Botan

#if defined(BOTAN_BUILD_COMPILER_IS_MSVC)
   #include <intrin.h>
#endif

namespace Botan {

/**
* Perform a 64x64->128 bit multiplication
*/
constexpr inline void mul64x64_128(uint64_t a, uint64_t b, uint64_t* lo, uint64_t* hi) {
   if(!std::is_constant_evaluated()) {
#if defined(BOTAN_BUILD_COMPILER_IS_MSVC) && defined(BOTAN_TARGET_ARCH_IS_X86_64)
      *lo = _umul128(a, b, hi);
      return;

#elif defined(BOTAN_BUILD_COMPILER_IS_MSVC) && defined(BOTAN_TARGET_ARCH_IS_ARM64)
      *lo = a * b;
      *hi = __umulh(a, b);
      return;
#endif
   }

#if defined(BOTAN_TARGET_HAS_NATIVE_UINT128)
   const uint128_t r = static_cast<uint128_t>(a) * b;
   *hi = (r >> 64) & 0xFFFFFFFFFFFFFFFF;
   *lo = (r) & 0xFFFFFFFFFFFFFFFF;
#else

   /*
   * Do a 64x64->128 multiply using four 32x32->64 multiplies plus
   * some adds and shifts.
   */
   const size_t HWORD_BITS = 32;
   const uint32_t HWORD_MASK = 0xFFFFFFFF;

   const uint32_t a_hi = (a >> HWORD_BITS);
   const uint32_t a_lo = (a & HWORD_MASK);
   const uint32_t b_hi = (b >> HWORD_BITS);
   const uint32_t b_lo = (b & HWORD_MASK);

   const uint64_t x0 = static_cast<uint64_t>(a_hi) * b_hi;
   const uint64_t x1 = static_cast<uint64_t>(a_lo) * b_hi;
   const uint64_t x2 = static_cast<uint64_t>(a_hi) * b_lo;
   const uint64_t x3 = static_cast<uint64_t>(a_lo) * b_lo;

   // this cannot overflow as (2^32-1)^2 + 2^32-1 + 2^32-1 = 2^64-1
   const uint64_t middle = x2 + (x3 >> HWORD_BITS) + (x1 & HWORD_MASK);

   // likewise these cannot overflow
   *hi = x0 + (middle >> HWORD_BITS) + (x1 >> HWORD_BITS);
   *lo = (middle << HWORD_BITS) + (x3 & HWORD_MASK);
#endif
}

}  // namespace Botan

namespace Botan {

class donna128 final {
   public:
      constexpr explicit donna128(uint64_t l = 0, uint64_t h = 0) : m_lo(l), m_hi(h) {}

      template <std::unsigned_integral T>
      constexpr friend donna128 operator>>(const donna128& x, T shift) {
         donna128 z = x;

         if(shift > 64) {
            z.m_lo = z.m_hi >> (shift - 64);
            z.m_hi = 0;
         } else if(shift == 64) {
            z.m_lo = z.m_hi;
            z.m_hi = 0;
         } else if(shift > 0) {
            const uint64_t carry = z.m_hi << static_cast<size_t>(64 - shift);
            z.m_hi >>= shift;
            z.m_lo >>= shift;
            z.m_lo |= carry;
         }

         return z;
      }

      template <std::unsigned_integral T>
      constexpr friend donna128 operator<<(const donna128& x, T shift) {
         donna128 z = x;
         if(shift > 64) {
            z.m_hi = z.m_lo << (shift - 64);
            z.m_lo = 0;
         } else if(shift == 64) {
            z.m_hi = z.m_lo;
            z.m_lo = 0;
         } else if(shift > 0) {
            const uint64_t carry = z.m_lo >> static_cast<size_t>(64 - shift);
            z.m_lo = (z.m_lo << shift);
            z.m_hi = (z.m_hi << shift) | carry;
         }

         return z;
      }

      constexpr friend uint64_t operator&(const donna128& x, uint64_t mask) { return x.m_lo & mask; }

      constexpr uint64_t operator&=(uint64_t mask) {
         m_hi = 0;
         m_lo &= mask;
         return m_lo;
      }

      constexpr donna128& operator+=(const donna128& x) {
         m_lo += x.m_lo;
         m_hi += x.m_hi;

         const uint64_t carry = CT::Mask<uint64_t>::is_lt(m_lo, x.m_lo).if_set_return(1);
         m_hi += carry;
         return *this;
      }

      constexpr donna128& operator+=(uint64_t x) {
         m_lo += x;
         const uint64_t carry = CT::Mask<uint64_t>::is_lt(m_lo, x).if_set_return(1);
         m_hi += carry;
         return *this;
      }

      constexpr uint64_t lo() const { return m_lo; }

      constexpr uint64_t hi() const { return m_hi; }

      constexpr explicit operator uint64_t() const { return lo(); }

   private:
      uint64_t m_lo = 0;
      uint64_t m_hi = 0;
};

template <std::integral T>
constexpr inline donna128 operator*(const donna128& x, T y) {
   BOTAN_ARG_CHECK(x.hi() == 0, "High 64 bits of donna128 set to zero during multiply");

   uint64_t lo = 0;
   uint64_t hi = 0;
   mul64x64_128(x.lo(), static_cast<uint64_t>(y), &lo, &hi);
   return donna128(lo, hi);
}

template <std::integral T>
constexpr inline donna128 operator*(T y, const donna128& x) {
   return x * y;
}

constexpr inline donna128 operator+(const donna128& x, const donna128& y) {
   donna128 z = x;
   z += y;
   return z;
}

constexpr inline donna128 operator+(const donna128& x, uint64_t y) {
   donna128 z = x;
   z += y;
   return z;
}

constexpr inline donna128 operator|(const donna128& x, const donna128& y) {
   return donna128(x.lo() | y.lo(), x.hi() | y.hi());
}

constexpr inline donna128 operator|(const donna128& x, uint64_t y) {
   return donna128(x.lo() | y, x.hi());
}

constexpr inline uint64_t carry_shift(const donna128& a, size_t shift) {
   return (a >> shift).lo();
}

constexpr inline uint64_t combine_lower(const donna128& a, size_t s1, const donna128& b, size_t s2) {
   const donna128 z = (a >> s1) | (b << s2);
   return z.lo();
}

#if defined(BOTAN_TARGET_HAS_NATIVE_UINT128)
inline uint64_t carry_shift(const uint128_t a, size_t shift) {
   return static_cast<uint64_t>(a >> shift);
}

inline uint64_t combine_lower(const uint128_t a, size_t s1, const uint128_t b, size_t s2) {
   return static_cast<uint64_t>((a >> s1) | (b << s2));
}
#endif

}  // namespace Botan

namespace Botan {

/**
* No_Filesystem_Access Exception
*/
class No_Filesystem_Access final : public Exception {
   public:
      No_Filesystem_Access() : Exception("No filesystem access enabled.") {}
};

BOTAN_TEST_API bool has_filesystem_impl();

BOTAN_TEST_API std::vector<std::string> get_files_recursive(std::string_view dir);

}  // namespace Botan

namespace Botan {

namespace fmt_detail {

inline void do_fmt(std::ostringstream& oss, std::string_view format) {
   oss << format;
}

template <typename T, typename... Ts>
void do_fmt(std::ostringstream& oss, std::string_view format, const T& val, const Ts&... rest) {
   size_t i = 0;

   while(i < format.size()) {
      if(format[i] == '{' && (format.size() > (i + 1)) && format.at(i + 1) == '}') {
         oss << val;
         return do_fmt(oss, format.substr(i + 2), rest...);
      } else {
         oss << format[i];
      }

      i += 1;
   }
}

}  // namespace fmt_detail

/**
* Simple formatter utility.
*
* Should be replaced with std::format once that's available on all our
* supported compilers.
*
* '{}' markers in the format string are replaced by the arguments.
* Unlike std::format, there is no support for escaping or for any kind
* of conversion flags.
*/
template <typename... T>
std::string fmt(std::string_view format, const T&... args) {
   std::ostringstream oss;
   oss.imbue(std::locale::classic());
   fmt_detail::do_fmt(oss, format, args...);
   return oss.str();
}

}  // namespace Botan


namespace Botan {

class StreamCipher;
class GHASH;

/**
* GCM Mode
*/
class GCM_Mode : public AEAD_Mode /* NOLINT(*-special-member-functions) */ {
   public:
      void set_associated_data_n(size_t idx, std::span<const uint8_t> ad) final;

      std::string name() const final;

      size_t update_granularity() const final;

      size_t ideal_granularity() const final;

      Key_Length_Specification key_spec() const final;

      bool valid_nonce_length(size_t len) const final;

      size_t tag_size() const final { return m_tag_size; }

      void clear() final;

      void reset() final;

      std::string provider() const final;

      bool has_keying_material() const final;

      ~GCM_Mode() override;

   protected:
      GCM_Mode(std::unique_ptr<BlockCipher> cipher, size_t tag_size);

      static const size_t GCM_BS = 16;

      const size_t m_tag_size;          // NOLINT(*non-private-member-variable*)
      const std::string m_cipher_name;  // NOLINT(*non-private-member-variable*)

      std::unique_ptr<StreamCipher> m_ctr;  // NOLINT(*non-private-member-variable*)
      std::unique_ptr<GHASH> m_ghash;       // NOLINT(*non-private-member-variable*)
      bool m_in_msg = false;                // NOLINT(*non-private-member-variable*)

   private:
      void start_msg(const uint8_t nonce[], size_t nonce_len) override;

      void key_schedule(std::span<const uint8_t> key) override;
};

/**
* GCM Encryption
*/
class GCM_Encryption final : public GCM_Mode {
   public:
      /**
      * @param cipher the 128 bit block cipher to use
      * @param tag_size is how big the auth tag will be
      */
      explicit GCM_Encryption(std::unique_ptr<BlockCipher> cipher, size_t tag_size = 16) :
            GCM_Mode(std::move(cipher), tag_size) {}

      size_t output_length(size_t input_length) const override;

      size_t minimum_final_size() const override { return 0; }

   private:
      size_t process_msg(uint8_t buf[], size_t size) override;
      void finish_msg(secure_vector<uint8_t>& final_block, size_t offset = 0) override;
};

/**
* GCM Decryption
*/
class GCM_Decryption final : public GCM_Mode {
   public:
      /**
      * @param cipher the 128 bit block cipher to use
      * @param tag_size is how big the auth tag will be
      */
      explicit GCM_Decryption(std::unique_ptr<BlockCipher> cipher, size_t tag_size = 16) :
            GCM_Mode(std::move(cipher), tag_size) {}

      size_t output_length(size_t input_length) const override;

      size_t minimum_final_size() const override { return tag_size(); }

   private:
      size_t process_msg(uint8_t buf[], size_t size) override;
      void finish_msg(secure_vector<uint8_t>& final_block, size_t offset = 0) override;
};

}  // namespace Botan

namespace Botan {

// Helper for defining GFNI constants
consteval uint64_t gfni_matrix(std::string_view s) {
   uint64_t matrix = 0;
   size_t bit_cnt = 0;
   uint8_t row = 0;

   for(const char c : s) {
      if(c == ' ' || c == '\n') {
         continue;
      }
      if(c != '0' && c != '1') {
         throw std::runtime_error("gfni_matrix: invalid bit value");
      }

      if(c == '1') {
         row |= 0x80 >> (7 - bit_cnt % 8);
      }
      bit_cnt++;

      if(bit_cnt % 8 == 0) {
         matrix <<= 8;
         matrix |= row;
         row = 0;
      }
   }

   if(bit_cnt != 64) {
      throw std::runtime_error("gfni_matrix: invalid bit count");
   }

   return matrix;
}

}  // namespace Botan

namespace Botan {

/**
* GCM's GHASH
*/
class GHASH final : public SymmetricAlgorithm {
   private:
      static constexpr size_t GCM_BS = 16;

   public:
      /// Hashing of non-default length nonce values for both GCM and GMAC use-cases
      void nonce_hash(std::span<uint8_t, GCM_BS> y0, std::span<const uint8_t> nonce);

      void start(std::span<const uint8_t> nonce);

      void update(std::span<const uint8_t> in);

      /// Monolithic setting of associated data usid in the GCM use-case
      void set_associated_data(std::span<const uint8_t> ad);

      /// Incremental update of associated data used in the GMAC use-case
      void update_associated_data(std::span<const uint8_t> ad);

      /// Reset the AAD state without resetting the key (used in GMAC::final_result)
      void reset_associated_data();

      void final(std::span<uint8_t> out);

      Key_Length_Specification key_spec() const override { return Key_Length_Specification(16); }

      bool has_keying_material() const override;

      void clear() override;

      /// Reset the per-message state (nonce/ghash/text-len/buffer) but
      /// preserve any associated data set via set_associated_data
      void reset_state();

      std::string name() const override { return "GHASH"; }

      std::string provider() const;

   private:
      void ghash_update(std::span<uint8_t, GCM_BS> x, std::span<const uint8_t> input);
      void ghash_zeropad(std::span<uint8_t, GCM_BS> x);
      void ghash_final_block(std::span<uint8_t, GCM_BS> x, uint64_t ad_len, uint64_t pt_len);

#if defined(BOTAN_HAS_GHASH_CLMUL_CPU)
      static void ghash_precompute_cpu(const uint8_t H[16], secure_vector<uint64_t>& H_pow);

      static void ghash_multiply_cpu(uint8_t x[16],
                                     secure_vector<uint64_t>& H_pow,
                                     const uint8_t input[],
                                     size_t blocks);
#endif

#if defined(BOTAN_HAS_GHASH_AVX512_CLMUL)
      static void ghash_precompute_avx512_clmul(const uint8_t H[16], uint64_t H_pow[16 * 2]);

      static void ghash_multiply_avx512_clmul(uint8_t x[16],
                                              const uint64_t H_pow[16 * 2],
                                              const uint8_t input[],
                                              size_t blocks);
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_VPERM)
      static void ghash_multiply_vperm(uint8_t x[16], const uint64_t HM[256], const uint8_t input[], size_t blocks);
#endif

      void key_schedule(std::span<const uint8_t> key) override;

      void ghash_multiply(std::span<uint8_t, GCM_BS> x, std::span<const uint8_t> input, size_t blocks);

      static void ghash_precompute_base(std::span<const uint8_t, GCM_BS> key, secure_vector<uint64_t>& HM);

      static void ghash_multiply_base(std::span<uint8_t, GCM_BS> x,
                                      const secure_vector<uint64_t>& HM,
                                      std::span<const uint8_t> input,
                                      size_t blocks);

      /// Polyval reuses the GHASH tables and kernels for its non-CLMUL fallback
      friend class Polyval;

   private:
      AlignmentBuffer<uint8_t, GCM_BS> m_buffer;

      /// cache of hash state after consuming the AD, reused for multiple messages
      std::array<uint8_t, GCM_BS> m_H_ad{};
      /// hash state used for update() or update_associated_data()
      std::array<uint8_t, GCM_BS> m_ghash{};
      secure_vector<uint64_t> m_HM;
      secure_vector<uint64_t> m_H_pow;

      std::optional<std::array<uint8_t, GCM_BS>> m_nonce;
      uint64_t m_ad_len = 0;
      uint64_t m_text_len = 0;
};

}  // namespace Botan

namespace Botan {

/**
* HKDF from RFC 5869.
*/
class HKDF final : public KDF {
   public:
      /**
      * @param prf MAC algorithm to use
      */
      explicit HKDF(std::unique_ptr<MessageAuthenticationCode> prf) : m_prf(std::move(prf)) {}

      std::unique_ptr<KDF> new_object() const override;

      std::string name() const override;

   private:
      void perform_kdf(std::span<uint8_t> key,
                       std::span<const uint8_t> secret,
                       std::span<const uint8_t> salt,
                       std::span<const uint8_t> label) const override;

   private:
      std::unique_ptr<MessageAuthenticationCode> m_prf;
};

/**
* HKDF Extraction Step from RFC 5869.
*/
class HKDF_Extract final : public KDF {
   public:
      /**
      * @param prf MAC algorithm to use
      */
      explicit HKDF_Extract(std::unique_ptr<MessageAuthenticationCode> prf) : m_prf(std::move(prf)) {}

      std::unique_ptr<KDF> new_object() const override;

      std::string name() const override;

   private:
      void perform_kdf(std::span<uint8_t> key,
                       std::span<const uint8_t> secret,
                       std::span<const uint8_t> salt,
                       std::span<const uint8_t> label) const override;

   private:
      std::unique_ptr<MessageAuthenticationCode> m_prf;
};

/**
* HKDF Expansion Step from RFC 5869.
*/
class HKDF_Expand final : public KDF {
   public:
      /**
      * @param prf MAC algorithm to use
      */
      explicit HKDF_Expand(std::unique_ptr<MessageAuthenticationCode> prf) : m_prf(std::move(prf)) {}

      std::unique_ptr<KDF> new_object() const override;

      std::string name() const override;

   private:
      void perform_kdf(std::span<uint8_t> key,
                       std::span<const uint8_t> secret,
                       std::span<const uint8_t> salt,
                       std::span<const uint8_t> label) const override;

   private:
      std::unique_ptr<MessageAuthenticationCode> m_prf;
};

/**
* HKDF-Expand-Label from TLS 1.3/QUIC
* @param hash_fn the hash to use
* @param secret the secret bits
* @param label the full label (no "TLS 1.3, " or "tls13 " prefix
*  is applied)
* @param hash_val the previous hash value (used for chaining, may be empty)
* @param length the desired output length
*/
secure_vector<uint8_t> BOTAN_TEST_API hkdf_expand_label(std::string_view hash_fn,
                                                        std::span<const uint8_t> secret,
                                                        std::string_view label,
                                                        std::span<const uint8_t> hash_val,
                                                        size_t length);

}  // namespace Botan

namespace Botan {

/**
* HMAC
*/
class HMAC final : public MessageAuthenticationCode {
   public:
      void clear() override;
      std::string name() const override;
      std::unique_ptr<MessageAuthenticationCode> new_object() const override;

      size_t output_length() const override;

      Key_Length_Specification key_spec() const override;

      bool has_keying_material() const override;

      /**
      * @param hash the hash to use for HMACing
      */
      explicit HMAC(std::unique_ptr<HashFunction> hash);

   private:
      void add_data(std::span<const uint8_t> input) override;
      void final_result(std::span<uint8_t> output) override;
      void start_msg(std::span<const uint8_t> nonce) override;
      void key_schedule(std::span<const uint8_t> key) override;

      std::unique_ptr<HashFunction> m_hash;
      secure_vector<uint8_t> m_ikey, m_okey;
      size_t m_hash_output_length;
      size_t m_hash_block_size;
};

}  // namespace Botan

namespace Botan {

template <std::unsigned_integral T>
constexpr inline std::optional<T> checked_add(T a, T b) {
   const T r = a + b;
   if(r < a || r < b) {
      return {};
   }
   return r;
}

template <std::unsigned_integral T>
constexpr std::optional<T> checked_sub(T a, T b) {
   if(b > a) {
      return {};
   }
   return a - b;
}

template <std::unsigned_integral T, std::unsigned_integral... Ts>
   requires all_same_v<T, Ts...>
constexpr inline std::optional<T> checked_add(T a, T b, Ts... rest) {
   if(auto r = checked_add(a, b)) {
      return checked_add(r.value(), rest...);
   } else {
      return {};
   }
}

template <std::unsigned_integral T>
constexpr inline std::optional<T> checked_mul(T a, T b) {
   // Multiplication by 1U is a hack to work around C's insane
   // integer promotion rules.
   // https://stackoverflow.com/questions/24795651
   const T r = (1U * a) * b;
   // If a == 0 then the multiply certainly did not overflow
   // Otherwise r / a == b unless overflow occurred
   if(a != 0 && r / a != b) {
      return {};
   }
   return r;
}

/**
* Add @p a and @p b, throwing Invalid_Argument with message @p msg if the
* addition would overflow.
*
* TODO(Botan4) add std::source_location argument
*/
template <std::unsigned_integral T>
constexpr T add_or_throw(T a, T b, std::string_view msg) {
   if(auto r = checked_add(a, b)) {
      return r.value();
   } else {
      throw Invalid_Argument(msg);
   }
}

/**
* Multiply @p a and @p b, throwing Invalid_Argument with message @p msg if the
* multiplication would overflow.
*
* TODO(Botan4) add std::source_location argument
*/
template <std::unsigned_integral T>
constexpr T mul_or_throw(T a, T b, std::string_view msg) {
   if(auto r = checked_mul(a, b)) {
      return r.value();
   } else {
      throw Invalid_Argument(msg);
   }
}

template <typename RT, typename ExceptionType, typename AT>
   requires std::integral<strong_type_wrapped_type<RT>> && std::integral<strong_type_wrapped_type<AT>>
constexpr RT checked_cast_to_or_throw(AT i, std::string_view error_msg_on_fail) {
   const auto unwrapped_input = unwrap_strong_type(i);

   const auto unwrapped_result = static_cast<strong_type_wrapped_type<RT>>(unwrapped_input);
   if(unwrapped_input != static_cast<strong_type_wrapped_type<AT>>(unwrapped_result)) [[unlikely]] {
      throw ExceptionType(error_msg_on_fail);
   }

   return wrap_strong_type<RT>(unwrapped_result);
}

template <typename RT, typename AT>
   requires std::integral<strong_type_wrapped_type<RT>> && std::integral<strong_type_wrapped_type<AT>>
constexpr RT checked_cast_to(AT i) {
   return checked_cast_to_or_throw<RT, Internal_Error>(i, "Error during integer conversion");
}

/**
* SWAR (SIMD within a word) byte-by-byte comparison
*
* This individually compares each byte of the provided words.
* It returns a mask which contains, for each byte, 0xFF if
* the byte in @p a was less than the byte in @p b. Otherwise the
* mask is 00.
*
* This implementation assumes that the high bits of each byte
* in both @p a and @p b are clear! It is possible to support the
* full range of bytes, but this requires additional comparisons.
*/
template <std::unsigned_integral T>
constexpr T swar_lt(T a, T b) {
   // The constant 0x808080... as a T
   constexpr T hi1 = (static_cast<T>(-1) / 255) << 7;
   // The constant 0x7F7F7F... as a T
   constexpr T lo7 = static_cast<T>(~hi1);
   T r = (lo7 - a + b) & hi1;
   // Currently the mask is 80 if lt, otherwise 00. Convert to FF/00
   return (r << 1) - (r >> 7);
}

/**
* SWAR (SIMD within a word) byte-by-byte comparison
*
* This individually compares each byte of the provided words.
* It returns a mask which contains, for each byte, 0x80 if
* the byte in @p a was less than the byte in @p b. Otherwise the
* mask is 00.
*
* This implementation assumes that the high bits of each byte
* in both @p lower and @p upper are clear! It is possible to support the
* full range of bytes, but this requires additional comparisons.
*/
template <std::unsigned_integral T>
constexpr T swar_in_range(T v, T lower, T upper) {
   // The constant 0x808080... as a T
   constexpr T hi1 = (static_cast<T>(-1) / 255) << 7;
   // The constant 0x7F7F7F... as a T
   constexpr T lo7 = ~hi1;

   const T sub = ((v | hi1) - (lower & lo7)) ^ ((v ^ (~lower)) & hi1);
   const T a_lo = sub & lo7;
   const T a_hi = sub & hi1;
   return (lo7 - a_lo + upper) & hi1 & ~a_hi;
}

/**
* Return the index of the first byte with the high bit set
*/
template <std::unsigned_integral T>
constexpr size_t index_of_first_set_byte(T v) {
   // The constant 0x010101... as a T
   constexpr T lo1 = (static_cast<T>(-1) / 255);
   // The constant 0x808080... as a T
   constexpr T hi1 = lo1 << 7;
   // How many bits to shift in order to get the top byte
   constexpr size_t bits = (sizeof(T) * 8) - 8;

   return static_cast<size_t>((((((v & hi1) - 1) & lo1) * lo1) >> bits) - 1);
}

}  // namespace Botan

/*
* GCC and Clang use string identifiers to tag ISA extensions (eg using the
* `target` function attribute).
*
* This file consolidates the actual definition of such target attributes
*/

#if defined(BOTAN_TARGET_ARCH_IS_X86_FAMILY)

   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("ssse3")
   #define BOTAN_FN_ISA_SIMD_2X64 BOTAN_FUNC_ISA("ssse3")
   #define BOTAN_FN_ISA_SIMD_4X64 BOTAN_FUNC_ISA("avx2")
   #define BOTAN_FN_ISA_SIMD_8X64 BOTAN_FN_ISA_AVX512
   #define BOTAN_FN_ISA_CLMUL BOTAN_FUNC_ISA("pclmul,ssse3")
   #define BOTAN_FN_ISA_AESNI BOTAN_FUNC_ISA("aes,ssse3")
   #define BOTAN_FN_ISA_SHANI BOTAN_FUNC_ISA("sha,ssse3,sse4.1")
   #define BOTAN_FN_ISA_SHA512 BOTAN_FUNC_ISA("sha512,avx2")
   #define BOTAN_FN_ISA_BMI2 BOTAN_FUNC_ISA("bmi,bmi2")
   #define BOTAN_FN_ISA_RNG BOTAN_FUNC_ISA("rdrnd")
   #define BOTAN_FN_ISA_SSE2 BOTAN_FUNC_ISA("sse2")
   #define BOTAN_FN_ISA_AVX2 BOTAN_FUNC_ISA("avx2")
   #define BOTAN_FN_ISA_AVX2_BMI2 BOTAN_FUNC_ISA("avx2,bmi,bmi2")
   #define BOTAN_FN_ISA_AVX2_GFNI BOTAN_FUNC_ISA("avx2,gfni")
   #define BOTAN_FN_ISA_AVX2_VAES BOTAN_FUNC_ISA("vaes,avx2")
   #define BOTAN_FN_ISA_AVX2_SM3 BOTAN_FUNC_ISA("sm3,avx2")
   #define BOTAN_FN_ISA_AVX2_SM4 BOTAN_FUNC_ISA("sm4,avx2")
   #define BOTAN_FN_ISA_AVX512 \
      BOTAN_FUNC_ISA("avx512f,avx512dq,avx512bw,avx512vl,avx512vbmi,avx512vbmi2,avx512bitalg,avx512ifma")
   #define BOTAN_FN_ISA_AVX512_CLMUL \
      BOTAN_FUNC_ISA("avx512f,avx512dq,avx512bw,avx512vl,avx512vbmi,avx512vbmi2,avx512bitalg,pclmul,vpclmulqdq")
   #define BOTAN_FN_ISA_AVX512_BMI2 \
      BOTAN_FUNC_ISA("avx512f,avx512dq,avx512bw,avx512vl,avx512vbmi,avx512vbmi2,avx512bitalg,avx512ifma,bmi,bmi2")
   #define BOTAN_FN_ISA_AVX512_GFNI \
      BOTAN_FUNC_ISA("avx512f,avx512dq,avx512bw,avx512vl,avx512vbmi,avx512vbmi2,avx512bitalg,avx512ifma,gfni")

   #define BOTAN_FN_ISA_HWAES BOTAN_FN_ISA_AESNI
#endif

#if defined(BOTAN_TARGET_ARCH_IS_ARM64)

   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("+simd")
   #define BOTAN_FN_ISA_CLMUL BOTAN_FUNC_ISA("+crypto+aes")
   #define BOTAN_FN_ISA_AES BOTAN_FUNC_ISA("+crypto+aes")
   #define BOTAN_FN_ISA_SHA2 BOTAN_FUNC_ISA("+crypto+sha2")
   #define BOTAN_FN_ISA_SM3 BOTAN_FUNC_ISA("arch=armv8.2-a+sm4")
   #define BOTAN_FN_ISA_SM4 BOTAN_FUNC_ISA("arch=armv8.2-a+sm4")
   #define BOTAN_FN_ISA_SHA512 BOTAN_FUNC_ISA("arch=armv8.2-a+sha3")

   #define BOTAN_FN_ISA_HWAES BOTAN_FN_ISA_AES
#endif

#if defined(BOTAN_TARGET_ARCH_IS_ARM32)
   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("fpu=neon")
#endif

#if defined(BOTAN_TARGET_ARCH_IS_PPC_FAMILY)

   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("altivec")
   #define BOTAN_FN_ISA_CLMUL BOTAN_FUNC_ISA("vsx,crypto")
   #define BOTAN_FN_ISA_AES BOTAN_FUNC_ISA("vsx,crypto")
   #define BOTAN_FN_ISA_RNG BOTAN_FUNC_ISA("cpu=power9")

   #define BOTAN_FN_ISA_HWAES BOTAN_FN_ISA_AES
#endif

#if defined(BOTAN_TARGET_ARCH_IS_LOONGARCH64)

   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("lsx")

#endif

#if defined(BOTAN_TARGET_ARCH_IS_WASM)

   #define BOTAN_FN_ISA_SIMD_4X32 BOTAN_FUNC_ISA("simd128")
   #define BOTAN_FN_ISA_SIMD_2X64 BOTAN_FUNC_ISA("simd128")

#endif

/**
 * @file loadstor.h
 *
 * @brief This header contains various helper functions to load and store
 *        unsigned integers in big- or little-endian byte order.
 *
 * Storing integer values in various ways (same for BE and LE):
 * @code {.cpp}
 *
 *   std::array<uint8_t, 8> bytes = store_le(some_uint64);
 *   std::array<uint8_t, 12> bytes = store_le(some_uint32_1, some_uint32_2, some_uint32_3, ...);
 *   auto bytes = store_le<std::vector<uint8_t>>(some_uint64);
 *   auto bytes = store_le<MyContainerStrongType>(some_uint64);
 *   auto bytes = store_le<std::vector<uint8_t>>(vector_of_ints);
 *   auto bytes = store_le<secure_vector<uint8_t>>(some_uint32_1, some_uint32_2, some_uint32_3, ...);
 *   store_le(bytes, some_uint64);
 *   store_le(concatenated_bytes, some_uint64_1, some_uint64_2, some_uint64_3, ...);
 *   store_le(concatenated_bytes, vector_of_ints);
 *   copy_out_le(short_concated_bytes, vector_of_ints); // stores as many bytes as required in the output buffer
 *
 * @endcode
 *
 * Loading integer values in various ways (same for BE and LE):
 * @code {.cpp}
 *
 *   uint64_t some_uint64 = load_le(bytes_8);
 *   auto some_int32s = load_le<std::vector<uint32_t>>(concatenated_bytes);
 *   auto some_int32s = load_le<std::vector<MyIntStrongType>>(concatenated_bytes);
 *   auto some_int32s = load_le(some_strong_typed_bytes);
 *   auto strong_int  = load_le<MyStrongTypedInteger>(concatenated_bytes);
 *   load_le(concatenated_bytes, out_some_uint64);
 *   load_le(concatenated_bytes, out_some_uint64_1, out_some_uint64_2, out_some_uint64_3, ...);
 *   load_le(out_vector_of_ints, concatenated_bytes);
 *
 * @endcode
 */

namespace Botan {

static_assert(std::endian::native == std::endian::big || std::endian::native == std::endian::little,
              "Mixed endian systems are not supported");

/**
* Byte extraction
* @param byte_num which byte to extract, 0 == highest byte
* @param input the value to extract from
* @return byte byte_num of input
*/
template <typename T>
inline constexpr uint8_t get_byte_var(size_t byte_num, T input) {
   return static_cast<uint8_t>(input >> (((~byte_num) & (sizeof(T) - 1)) << 3));
}

/**
* Byte extraction
* @param input the value to extract from
* @return byte byte number B of input
*/
template <size_t B, typename T>
inline constexpr uint8_t get_byte(T input)
   requires(B < sizeof(T))
{
   const size_t shift = ((~B) & (sizeof(T) - 1)) << 3;
   return static_cast<uint8_t>((input >> shift) & 0xFF);
}

/**
* Make a uint16_t from two bytes
* @param i0 the first byte
* @param i1 the second byte
* @return i0 || i1
*/
inline constexpr uint16_t make_uint16(uint8_t i0, uint8_t i1) {
   return static_cast<uint16_t>((static_cast<uint16_t>(i0) << 8) | i1);
}

/**
* Make a uint32_t from four bytes
* @param i0 the first byte
* @param i1 the second byte
* @param i2 the third byte
* @param i3 the fourth byte
* @return i0 || i1 || i2 || i3
*/
inline constexpr uint32_t make_uint32(uint8_t i0, uint8_t i1, uint8_t i2, uint8_t i3) {
   return ((static_cast<uint32_t>(i0) << 24) | (static_cast<uint32_t>(i1) << 16) | (static_cast<uint32_t>(i2) << 8) |
           (static_cast<uint32_t>(i3)));
}

/**
* Make a uint64_t from eight bytes
* @param i0 the first byte
* @param i1 the second byte
* @param i2 the third byte
* @param i3 the fourth byte
* @param i4 the fifth byte
* @param i5 the sixth byte
* @param i6 the seventh byte
* @param i7 the eighth byte
* @return i0 || i1 || i2 || i3 || i4 || i5 || i6 || i7
*/
inline constexpr uint64_t make_uint64(
   uint8_t i0, uint8_t i1, uint8_t i2, uint8_t i3, uint8_t i4, uint8_t i5, uint8_t i6, uint8_t i7) {
   return ((static_cast<uint64_t>(i0) << 56) | (static_cast<uint64_t>(i1) << 48) | (static_cast<uint64_t>(i2) << 40) |
           (static_cast<uint64_t>(i3) << 32) | (static_cast<uint64_t>(i4) << 24) | (static_cast<uint64_t>(i5) << 16) |
           (static_cast<uint64_t>(i6) << 8) | (static_cast<uint64_t>(i7)));
}

namespace detail {

/**
 * @returns the opposite endianness of the specified endianness
 *
 * Note this assumes that there are only two endian orderings; we
 * do not supported mixed endian systems
 */
consteval std::endian opposite(std::endian endianness) {
   if(endianness == std::endian::big) {
      return std::endian::little;
   } else {
      // We already verified via static assert earlier in this file that we are
      // running on either a big endian or little endian system
      return std::endian::big;
   }
}

/**
 * Models a custom type that provides factory methods to be loaded in big- or
 * little-endian byte order.
 */
template <typename T>
concept custom_loadable = requires(std::span<const uint8_t, sizeof(T)> data) {
   { T::load_be(data) } -> std::same_as<T>;
   { T::load_le(data) } -> std::same_as<T>;
};

/**
 * Models a custom type that provides store methods to be stored in big- or
 * little-endian byte order.
 */
template <typename T>
concept custom_storable = requires(std::span<uint8_t, sizeof(T)> data, const T value) {
   { value.store_be(data) };
   { value.store_le(data) };
};

/**
 * Models a type that can be loaded/stored from/to a byte range.
 */
template <typename T>
concept unsigned_integralish =
   std::unsigned_integral<strong_type_wrapped_type<T>> ||
   (std::is_enum_v<T> && std::unsigned_integral<std::underlying_type_t<T>>) ||
   (custom_loadable<strong_type_wrapped_type<T>> || custom_storable<strong_type_wrapped_type<T>>);

template <typename T>
struct wrapped_type_helper_with_enum {
      using type = strong_type_wrapped_type<T>;
};

template <typename T>
   requires std::is_enum_v<T>
struct wrapped_type_helper_with_enum<T> {
      using type = std::underlying_type_t<T>;
};

template <unsigned_integralish T>
using wrapped_type = typename wrapped_type_helper_with_enum<T>::type;

template <unsigned_integralish InT>
constexpr auto unwrap_strong_type_or_enum(InT t) {
   if constexpr(std::is_enum_v<InT>) {
      // TODO: C++23: use std::to_underlying(in) instead
      return static_cast<std::underlying_type_t<InT>>(t);
   } else {
      return Botan::unwrap_strong_type(t);
   }
}

template <unsigned_integralish OutT, std::unsigned_integral T>
constexpr auto wrap_strong_type_or_enum(T t) {
   if constexpr(std::is_enum_v<OutT>) {
      return static_cast<OutT>(t);
   } else {
      return Botan::wrap_strong_type<OutT>(t);
   }
}

/**
 * Manually load a word from a range in either big or little endian byte order.
 *
 * This is only used at compile time.
 */
template <std::endian endianness, std::unsigned_integral OutT, ranges::contiguous_range<uint8_t> InR>
inline constexpr OutT fallback_load_any(const InR& in_range) {
   std::span in{in_range};
   // clang-format off
   if constexpr(endianness == std::endian::big) {
      return [&]<size_t... i>(std::index_sequence<i...>) {
         return static_cast<OutT>(((static_cast<OutT>(in[i]) << ((sizeof(OutT) - i - 1) * 8)) | ...));
      } (std::make_index_sequence<sizeof(OutT)>());
   } else {
      static_assert(endianness == std::endian::little);
      return [&]<size_t... i>(std::index_sequence<i...>) {
         return static_cast<OutT>(((static_cast<OutT>(in[i]) << (i * 8)) | ...));
      } (std::make_index_sequence<sizeof(OutT)>());
   }
   // clang-format on
}

/**
 * Manually store a word into a range in either big or little endian byte order.
 *
 * This will be used only at compile time.
 */
template <std::endian endianness, std::unsigned_integral InT, ranges::contiguous_output_range<uint8_t> OutR>
inline constexpr void fallback_store_any(InT in, OutR&& out_range /* NOLINT(*-std-forward) */) {
   std::span out{out_range};
   // clang-format off
   if constexpr(endianness == std::endian::big) {
      [&]<size_t... i>(std::index_sequence<i...>) {
         ((out[i] = get_byte<i>(in)), ...);
      } (std::make_index_sequence<sizeof(InT)>());
   } else {
      static_assert(endianness == std::endian::little);
      [&]<size_t... i>(std::index_sequence<i...>) {
         ((out[i] = get_byte<sizeof(InT) - i - 1>(in)), ...);
      } (std::make_index_sequence<sizeof(InT)>());
   }
   // clang-format on
}

/**
 * Load a word from a range in either big or little endian byte order
 *
 * This is the base implementation, all other overloads are just convenience
 * wrappers. It is assumed that the range has the correct size for the word.
 *
 * Template arguments of all overloads of load_any() share the same semantics:
 *
 *   1.  std::endian     Either `std::endian::big` or `std::endian::little`, that
 *                       will eventually select the byte order translation mode
 *                       implemented in this base function.
 *
 *   2.  Output type     Either `AutoDetect`, an unsigned integer or a container
 *                       holding an unsigned integer type. `AutoDetect` means
 *                       that the caller did not explicitly specify the type and
 *                       expects the type to be inferred from the input.
 *
 *   3+. Argument types  Typically, those are input and output ranges of bytes
 *                       or unsigned integers. Or one or more unsigned integers
 *                       acting as output parameters.
 *
 * @param in_range a fixed-length byte range
 * @return T loaded from @p in_range, as a big-endian value
 */
template <std::endian endianness, unsigned_integralish WrappedOutT, ranges::contiguous_range<uint8_t> InR>
   requires(!custom_loadable<strong_type_wrapped_type<WrappedOutT>>)
inline constexpr WrappedOutT load_any(InR&& in_range) {
   using OutT = detail::wrapped_type<WrappedOutT>;
   ranges::assert_exact_byte_length<sizeof(OutT)>(in_range);

   return detail::wrap_strong_type_or_enum<WrappedOutT>([&]() -> OutT {
      // At compile time we cannot use `typecast_copy` as it uses `std::memcpy`
      // internally to copy ranges on a byte-by-byte basis, which is not allowed
      // in a `constexpr` context.
      if(std::is_constant_evaluated()) /* TODO: C++23: if consteval {} */ {
         return fallback_load_any<endianness, OutT>(std::forward<InR>(in_range));
      } else {
         const std::span in{in_range};
         if constexpr(sizeof(OutT) == 1) {
            return static_cast<OutT>(in[0]);
         } else if constexpr(endianness == std::endian::native) {
            return typecast_copy<OutT>(in);
         } else {
            static_assert(opposite(endianness) == std::endian::native);
            return reverse_bytes(typecast_copy<OutT>(in));
         }
      }
   }());
}

/**
 * Load a custom object from a range in either big or little endian byte order
 *
 * This is the base implementation for custom objects (e.g. SIMD type wrappres),
 * all other overloads are just convenience overloads.
 *
 * @param in_range a fixed-length byte range
 * @return T loaded from @p in_range, as a big-endian value
 */
template <std::endian endianness, unsigned_integralish WrappedOutT, ranges::contiguous_range<uint8_t> InR>
   requires(custom_loadable<strong_type_wrapped_type<WrappedOutT>>)
inline constexpr WrappedOutT load_any(const InR& in_range) {
   using OutT = detail::wrapped_type<WrappedOutT>;
   ranges::assert_exact_byte_length<sizeof(OutT)>(in_range);
   const std::span<const uint8_t, sizeof(OutT)> ins{in_range};
   if constexpr(endianness == std::endian::big) {
      return wrap_strong_type<WrappedOutT>(OutT::load_be(ins));
   } else {
      return wrap_strong_type<WrappedOutT>(OutT::load_le(ins));
   }
}

/**
 * Load many unsigned integers
 * @param in   a fixed-length span to some bytes
 * @param outs a arbitrary-length parameter list of unsigned integers to be loaded
 */
template <std::endian endianness, typename OutT, ranges::contiguous_range<uint8_t> InR, unsigned_integralish... Ts>
   requires(sizeof...(Ts) > 0) && ((std::same_as<AutoDetect, OutT> && all_same_v<Ts...>) ||
                                   (unsigned_integralish<OutT> && all_same_v<OutT, Ts...>))
inline constexpr void load_any(const InR& in, Ts&... outs) {
   ranges::assert_exact_byte_length<(sizeof(Ts) + ...)>(in);
   auto load_one = [off = 0]<typename T>(auto i, T& o) mutable {
      o = load_any<endianness, T>(i.subspan(off).template first<sizeof(T)>());
      off += sizeof(T);
   };

   (load_one(std::span{in}, outs), ...);
}

/**
 * Load a variable number of words from @p in into @p out.
 * The byte length of the @p out and @p in ranges must match.
 *
 * @param out the output range of words
 * @param in the input range of bytes
 */
template <std::endian endianness,
          typename OutT,
          ranges::contiguous_output_range OutR,
          ranges::contiguous_range<uint8_t> InR>
   requires(unsigned_integralish<std::ranges::range_value_t<OutR>> &&
            (std::same_as<AutoDetect, OutT> || std::same_as<OutT, std::ranges::range_value_t<OutR>>))
inline constexpr void load_any(OutR&& out /* NOLINT(*-std-forward) */, const InR& in) {
   ranges::assert_equal_byte_lengths(out, in);
   using element_type = std::ranges::range_value_t<OutR>;

   auto load_elementwise = [&] {
      constexpr size_t bytes_per_element = sizeof(element_type);
      std::span<const uint8_t> in_s(in);
      for(auto& out_elem : out) {
         out_elem = load_any<endianness, element_type>(in_s.template first<bytes_per_element>());
         in_s = in_s.subspan(bytes_per_element);
      }
   };

   // At compile time we cannot use `typecast_copy` as it uses `std::memcpy`
   // internally to copy ranges on a byte-by-byte basis, which is not allowed
   // in a `constexpr` context.
   if(std::is_constant_evaluated()) /* TODO: C++23: if consteval {} */ {
      load_elementwise();
   } else {
      if constexpr(endianness == std::endian::native && !custom_loadable<element_type>) {
         typecast_copy(out, in);
      } else {
         load_elementwise();
      }
   }
}

//
// Type inference overloads
//

/**
 * Load one or more unsigned integers, auto-detect the output type if
 * possible. Otherwise, use the specified integer or integer container type.
 *
 * @param in_range a statically-sized range with some bytes
 * @return T loaded from in
 */
template <std::endian endianness, typename OutT, ranges::contiguous_range<uint8_t> InR>
   requires(std::same_as<AutoDetect, OutT> ||
            ((ranges::statically_spanable_range<OutT> || concepts::resizable_container<OutT>) &&
             unsigned_integralish<typename OutT::value_type>))
inline constexpr auto load_any(InR&& in_range) {
   auto out = []([[maybe_unused]] const auto& in) {
      if constexpr(std::same_as<AutoDetect, OutT>) {
         if constexpr(ranges::statically_spanable_range<InR>) {
            constexpr size_t extent = decltype(std::span{in})::extent;

            // clang-format off
            using type =
               std::conditional_t<extent == 1, uint8_t,
               std::conditional_t<extent == 2, uint16_t,
               std::conditional_t<extent == 4, uint32_t,
               std::conditional_t<extent == 8, uint64_t, void>>>>;
            // clang-format on

            static_assert(
               !std::is_void_v<type>,
               "Cannot determine the output type based on a statically sized bytearray with length other than those: 1, 2, 4, 8");

            return type{};
         } else {
            static_assert(
               !std::same_as<AutoDetect, OutT>,
               "cannot infer return type from a dynamic range at compile time, please specify it explicitly");
         }
      } else if constexpr(concepts::resizable_container<OutT>) {
         const size_t in_bytes = std::span{in}.size_bytes();
         constexpr size_t out_elem_bytes = sizeof(typename OutT::value_type);
         BOTAN_ARG_CHECK(in_bytes % out_elem_bytes == 0,
                         "Input range is not word-aligned with the requested output range");
         return OutT(in_bytes / out_elem_bytes);
      } else {
         return OutT{};
      }
   }(in_range);

   using out_type = decltype(out);
   if constexpr(unsigned_integralish<out_type>) {
      out = load_any<endianness, out_type>(std::forward<InR>(in_range));
   } else {
      static_assert(ranges::contiguous_range<out_type>);
      using out_range_type = std::ranges::range_value_t<out_type>;
      load_any<endianness, out_range_type>(out, std::forward<InR>(in_range));
   }
   return out;
}

//
// Legacy load functions that work on raw pointers and arrays
//

/**
 * Load a word from @p in at some offset @p off
 * @param in a pointer to some bytes
 * @param off an offset into the array
 * @return off'th T of in, as a big-endian value
 */
template <std::endian endianness, unsigned_integralish OutT>
inline constexpr OutT load_any(const uint8_t in[], size_t off) {
   // asserts that *in points to enough bytes to read at offset off
   constexpr size_t out_size = sizeof(OutT);
   return load_any<endianness, OutT>(std::span<const uint8_t, out_size>(in + off * out_size, out_size));
}

/**
 * Load many words from @p in
 * @param in   a pointer to some bytes
 * @param outs a arbitrary-length parameter list of unsigned integers to be loaded
 */
template <std::endian endianness, typename OutT, unsigned_integralish... Ts>
   requires(sizeof...(Ts) > 0 && all_same_v<Ts...> &&
            ((std::same_as<AutoDetect, OutT> && all_same_v<Ts...>) ||
             (unsigned_integralish<OutT> && all_same_v<OutT, Ts...>)))
inline constexpr void load_any(const uint8_t in[], Ts&... outs) {
   constexpr auto bytes = (sizeof(outs) + ...);
   // asserts that *in points to the correct amount of memory
   load_any<endianness, OutT>(std::span<const uint8_t, bytes>(in, bytes), outs...);
}

/**
 * Load a variable number of words from @p in into @p out.
 * @param out the output array of words
 * @param in the input array of bytes
 * @param count how many words are in in
 */
template <std::endian endianness, typename OutT, unsigned_integralish T>
   requires(std::same_as<AutoDetect, OutT> || std::same_as<T, OutT>)
inline constexpr void load_any(T out[], const uint8_t in[], size_t count) {
   // asserts that *in and *out point to the correct amount of memory
   load_any<endianness, OutT>(std::span<T>(out, count), std::span<const uint8_t>(in, count * sizeof(T)));
}

}  // namespace detail

/**
 * Load "something" in little endian byte order
 * See the documentation of this file for more details.
 */
template <typename OutT = detail::AutoDetect, typename... ParamTs>
inline constexpr auto load_le(ParamTs&&... params) {
   return detail::load_any<std::endian::little, OutT>(std::forward<ParamTs>(params)...);
}

/**
 * Load "something" in big endian byte order
 * See the documentation of this file for more details.
 */
template <typename OutT = detail::AutoDetect, typename... ParamTs>
inline constexpr auto load_be(ParamTs&&... params) {
   return detail::load_any<std::endian::big, OutT>(std::forward<ParamTs>(params)...);
}

namespace detail {

/**
 * Store a word in either big or little endian byte order into a range
 *
 * This is the base implementation, all other overloads are just convenience
 * wrappers. It is assumed that the range has the correct size for the word.
 *
 * Template arguments of all overloads of store_any() share the same semantics
 * as those of load_any(). See the documentation of this function for more
 * details.
 *
 * @param wrapped_in an unsigned integral to be stored
 * @param out_range  a byte range to store the word into
 */
template <std::endian endianness, unsigned_integralish WrappedInT, ranges::contiguous_output_range<uint8_t> OutR>
   requires(!custom_storable<strong_type_wrapped_type<WrappedInT>>)
inline constexpr void store_any(WrappedInT wrapped_in, OutR&& out_range) {
   const auto in = detail::unwrap_strong_type_or_enum(wrapped_in);
   using InT = decltype(in);
   ranges::assert_exact_byte_length<sizeof(in)>(out_range);
   const std::span out{out_range};

   // At compile time we cannot use `typecast_copy` as it uses `std::memcpy`
   // internally to copy ranges on a byte-by-byte basis, which is not allowed
   // in a `constexpr` context.
   if(std::is_constant_evaluated()) /* TODO: C++23: if consteval {} */ {
      return fallback_store_any<endianness, InT>(in, std::forward<OutR>(out_range));
   } else {
      if constexpr(sizeof(InT) == 1) {
         out[0] = static_cast<uint8_t>(in);
      } else if constexpr(endianness == std::endian::native) {
         typecast_copy(out, in);
      } else {
         static_assert(opposite(endianness) == std::endian::native);
         typecast_copy(out, reverse_bytes(in));
      }
   }
}

/**
 * Store a custom word in either big or little endian byte order into a range
 *
 * This is the base implementation for storing custom objects, all other
 * overloads are just convenience overloads.
 *
 * @param wrapped_in a custom object to be stored
 * @param out_range  a byte range to store the word into
 */
template <std::endian endianness, unsigned_integralish WrappedInT, ranges::contiguous_output_range<uint8_t> OutR>
   requires(custom_storable<strong_type_wrapped_type<WrappedInT>>)
inline constexpr void store_any(WrappedInT wrapped_in, const OutR& out_range) {
   const auto in = detail::unwrap_strong_type_or_enum(wrapped_in);
   using InT = decltype(in);
   ranges::assert_exact_byte_length<sizeof(in)>(out_range);
   const std::span<uint8_t, sizeof(InT)> outs{out_range};
   if constexpr(endianness == std::endian::big) {
      in.store_be(outs);
   } else {
      in.store_le(outs);
   }
}

/**
 * Store many unsigned integers words into a byte range
 * @param out a sized range of some bytes
 * @param ins a arbitrary-length parameter list of unsigned integers to be stored
 */
template <std::endian endianness,
          typename InT,
          ranges::contiguous_output_range<uint8_t> OutR,
          unsigned_integralish... Ts>
   requires(sizeof...(Ts) > 0) && ((std::same_as<AutoDetect, InT> && all_same_v<Ts...>) ||
                                   (unsigned_integralish<InT> && all_same_v<InT, Ts...>))
inline constexpr void store_any(OutR&& out /* NOLINT(*-std-forward) */, Ts... ins) {
   ranges::assert_exact_byte_length<(sizeof(Ts) + ...)>(out);
   auto store_one = [off = 0]<typename T>(auto o, T i) mutable {
      store_any<endianness, T>(i, o.subspan(off).template first<sizeof(T)>());
      off += sizeof(T);
   };

   (store_one(std::span{out}, ins), ...);
}

/**
 * Store a variable number of words given in @p in into @p out.
 * The byte lengths of @p in and @p out must be consistent.
 * @param out the output range of bytes
 * @param in the input range of words
 */
template <std::endian endianness,
          typename InT,
          ranges::contiguous_output_range<uint8_t> OutR,
          ranges::spanable_range InR>
   requires(std::same_as<AutoDetect, InT> || std::same_as<InT, std::ranges::range_value_t<InR>>)
inline constexpr void store_any(OutR&& out /* NOLINT(*-std-forward) */, const InR& in) {
   ranges::assert_equal_byte_lengths(out, in);
   using element_type = std::ranges::range_value_t<InR>;

   auto store_elementwise = [&] {
      constexpr size_t bytes_per_element = sizeof(element_type);
      std::span<uint8_t> out_s(out);
      for(auto in_elem : in) {
         store_any<endianness, element_type>(out_s.template first<bytes_per_element>(), in_elem);
         out_s = out_s.subspan(bytes_per_element);
      }
   };

   // At compile time we cannot use `typecast_copy` as it uses `std::memcpy`
   // internally to copy ranges on a byte-by-byte basis, which is not allowed
   // in a `constexpr` context.
   if(std::is_constant_evaluated()) /* TODO: C++23: if consteval {} */ {
      store_elementwise();
   } else {
      if constexpr(endianness == std::endian::native && !custom_storable<element_type>) {
         typecast_copy(out, in);
      } else {
         store_elementwise();
      }
   }
}

//
// Type inference overloads
//

/**
 * Infer InT from a single unsigned integer input parameter.
 *
 * TODO: we might consider dropping this overload (i.e. out-range as second
 *       parameter) and make this a "special case" of the overload below, that
 *       takes a variadic number of input parameters.
 *
 * @param in an unsigned integer to be stored
 * @param out_range a range of bytes to store the word into
 */
template <std::endian endianness, typename InT, unsigned_integralish T, ranges::contiguous_output_range<uint8_t> OutR>
   requires std::same_as<AutoDetect, InT>
inline constexpr void store_any(T in, OutR&& out_range) {
   store_any<endianness, T>(in, std::forward<OutR>(out_range));
}

/**
 * The caller provided some integer values in a collection but did not provide
 * the output container. Let's create one for them, fill it with one of the
 * overloads above and return it. This will default to a std::array if the
 * caller did not specify the desired output container type.
 *
 * @param in_range a range of words that should be stored
 * @return a container of bytes that contains the stored words
 */
template <std::endian endianness, typename OutR, ranges::spanable_range InR>
   requires(std::same_as<AutoDetect, OutR> ||
            (ranges::statically_spanable_range<OutR> && std::default_initializable<OutR>) ||
            concepts::resizable_byte_buffer<OutR>)
inline constexpr auto store_any(InR&& in_range) {
   auto out = []([[maybe_unused]] const auto& in) {
      if constexpr(std::same_as<AutoDetect, OutR>) {
         if constexpr(ranges::statically_spanable_range<InR>) {
            constexpr size_t bytes = decltype(std::span{in})::extent * sizeof(std::ranges::range_value_t<InR>);
            return std::array<uint8_t, bytes>();
         } else {
            static_assert(
               !std::same_as<AutoDetect, OutR>,
               "cannot infer a suitable result container type from the given parameters at compile time, please specify it explicitly");
         }
      } else if constexpr(concepts::resizable_byte_buffer<OutR>) {
         return OutR(std::span{in}.size_bytes());
      } else {
         return OutR{};
      }
   }(in_range);

   store_any<endianness, std::ranges::range_value_t<InR>>(out, std::forward<InR>(in_range));
   return out;
}

/**
 * The caller provided some integer values but did not provide the output
 * container. Let's create one for them, fill it with one of the overloads above
 * and return it. This will default to a std::array if the caller did not
 * specify the desired output container type.
 *
 * @param ins some words that should be stored
 * @return a container of bytes that contains the stored words
 */
template <std::endian endianness, typename OutR, unsigned_integralish... Ts>
   requires all_same_v<Ts...>
inline constexpr auto store_any(Ts... ins) {
   return store_any<endianness, OutR>(std::array{ins...});
}

//
// Legacy store functions that work on raw pointers and arrays
//

/**
 * Store a single unsigned integer into a raw pointer
 * @param in the input unsigned integer
 * @param out the byte array to write to
 */
template <std::endian endianness, typename InT, unsigned_integralish T>
   requires(std::same_as<AutoDetect, InT> || std::same_as<T, InT>)
inline constexpr void store_any(T in, uint8_t out[]) {
   // asserts that *out points to enough bytes to write into
   store_any<endianness, InT>(in, std::span<uint8_t, sizeof(T)>(out, sizeof(T)));
}

/**
 * Store many unsigned integers words into a raw pointer
 * @param ins a arbitrary-length parameter list of unsigned integers to be stored
 * @param out the byte array to write to
 */
template <std::endian endianness, typename InT, unsigned_integralish T0, unsigned_integralish... Ts>
   requires(std::same_as<AutoDetect, InT> || std::same_as<T0, InT>) && all_same_v<T0, Ts...>
inline constexpr void store_any(uint8_t out[], T0 in0, Ts... ins) {
   constexpr auto bytes = sizeof(in0) + (sizeof(ins) + ... + 0);
   // asserts that *out points to the correct amount of memory
   store_any<endianness, T0>(std::span<uint8_t, bytes>(out, bytes), in0, ins...);
}

}  // namespace detail

/**
 * Store "something" in little endian byte order
 * See the documentation of this file for more details.
 */
template <typename ModifierT = detail::AutoDetect, typename... ParamTs>
inline constexpr auto store_le(ParamTs&&... params) {
   return detail::store_any<std::endian::little, ModifierT>(std::forward<ParamTs>(params)...);
}

/**
 * Store "something" in big endian byte order
 * See the documentation of this file for more details.
 */
template <typename ModifierT = detail::AutoDetect, typename... ParamTs>
inline constexpr auto store_be(ParamTs&&... params) {
   return detail::store_any<std::endian::big, ModifierT>(std::forward<ParamTs>(params)...);
}

namespace detail {

template <std::endian endianness, unsigned_integralish T>
inline size_t copy_out_any_word_aligned_portion(std::span<uint8_t>& out, std::span<const T>& in) {
   const size_t full_words = out.size() / sizeof(T);
   const size_t full_word_bytes = full_words * sizeof(T);
   const size_t remaining_bytes = out.size() - full_word_bytes;
   BOTAN_ASSERT_NOMSG(in.size_bytes() >= full_word_bytes + remaining_bytes);

   // copy full words
   store_any<endianness, T>(out.first(full_word_bytes), in.first(full_words));
   out = out.subspan(full_word_bytes);
   in = in.subspan(full_words);

   return remaining_bytes;
}

}  // namespace detail

/**
 * Partially copy a subset of @p in into @p out using big-endian
 * byte order.
 */
template <ranges::spanable_range InR>
inline void copy_out_be(std::span<uint8_t> out, const InR& in) {
   using T = std::ranges::range_value_t<InR>;
   std::span<const T> in_s{in};
   const auto remaining_bytes = detail::copy_out_any_word_aligned_portion<std::endian::big>(out, in_s);

   // copy remaining bytes as a partial word
   for(size_t i = 0; i < remaining_bytes; ++i) {
      out[i] = get_byte_var(i, in_s.front());
   }
}

/**
 * Partially copy a subset of @p in into @p out using little-endian
 * byte order.
 */
template <ranges::spanable_range InR>
inline void copy_out_le(std::span<uint8_t> out, const InR& in) {
   using T = std::ranges::range_value_t<InR>;
   std::span<const T> in_s{in};
   const auto remaining_bytes = detail::copy_out_any_word_aligned_portion<std::endian::little>(out, in_s);

   // copy remaining bytes as a partial word
   for(size_t i = 0; i < remaining_bytes; ++i) {
      out[i] = get_byte_var(sizeof(T) - 1 - i, in_s.front());
   }
}

}  // namespace Botan


namespace Botan {

enum class MD_Endian : uint8_t {
   Little,
   Big,
};

template <typename T>
concept md_hash_implementation =
   concepts::contiguous_container<typename T::digest_type> &&
   requires(typename T::digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
      { T::init(digest) } -> std::same_as<void>;
      { T::compress_n(digest, input, blocks) } -> std::same_as<void>;
      T::bit_endianness;
      T::byte_endianness;
      T::block_bytes;
      T::output_bytes;
      T::ctr_bytes;
   } && T::block_bytes >= 64 && is_power_of_2(T::block_bytes) && T::output_bytes >= 16 && T::ctr_bytes >= 8 &&
   is_power_of_2(T::ctr_bytes) && T::ctr_bytes < T::block_bytes;

template <md_hash_implementation MD>
class MerkleDamgard_Hash final {
   public:
      MerkleDamgard_Hash() { clear(); }

      void update(std::span<const uint8_t> input) {
         BufferSlicer in(input);

         while(!in.empty()) {
            if(const auto one_block = m_buffer.handle_unaligned_data(in)) {
               MD::compress_n(m_digest, one_block.value(), 1);
            }

            if(m_buffer.in_alignment()) {
               const auto [aligned_data, full_blocks] = m_buffer.aligned_data_to_process(in);
               if(full_blocks > 0) {
                  MD::compress_n(m_digest, aligned_data, full_blocks);
               }
            }
         }

         m_count += input.size();
      }

      void final(std::span<uint8_t> output) {
         append_padding_bit();
         append_counter_and_finalize();
         copy_output(output);
         clear();
      }

      void clear() {
         MD::init(m_digest);
         m_buffer.clear();
         m_count = 0;
      }

   private:
      void append_padding_bit() {
         BOTAN_ASSERT_NOMSG(!m_buffer.ready_to_consume());
         if constexpr(MD::bit_endianness == MD_Endian::Big) {
            const uint8_t final_byte = 0x80;
            m_buffer.append({&final_byte, 1});
         } else {
            const uint8_t final_byte = 0x01;
            m_buffer.append({&final_byte, 1});
         }
      }

      void append_counter_and_finalize() {
         // Compress the remaining data if the final data block does not provide
         // enough space for the counter bytes.
         if(m_buffer.elements_until_alignment() < MD::ctr_bytes) {
            m_buffer.fill_up_with_zeros();
            MD::compress_n(m_digest, m_buffer.consume(), 1);
         }

         // Make sure that any remaining bytes in the very last block are zero.
         BOTAN_ASSERT_NOMSG(m_buffer.elements_until_alignment() >= MD::ctr_bytes);
         m_buffer.fill_up_with_zeros();

         // Replace a bunch of the right-most zero-padding with the counter bytes.
         const uint64_t bit_count = m_count * 8;
         auto last_bytes = m_buffer.directly_modify_last(sizeof(bit_count));
         if constexpr(MD::byte_endianness == MD_Endian::Big) {
            store_be(bit_count, last_bytes.data());
         } else {
            store_le(bit_count, last_bytes.data());
         }

         // Compress the very last block.
         MD::compress_n(m_digest, m_buffer.consume(), 1);
      }

      void copy_output(std::span<uint8_t> output) {
         BOTAN_ASSERT_NOMSG(output.size() >= MD::output_bytes);

         if constexpr(MD::byte_endianness == MD_Endian::Big) {
            copy_out_be(output.first(MD::output_bytes), m_digest);
         } else {
            copy_out_le(output.first(MD::output_bytes), m_digest);
         }
      }

   private:
      typename MD::digest_type m_digest;
      uint64_t m_count = 0;

      AlignmentBuffer<uint8_t, MD::block_bytes> m_buffer;
};

}  // namespace Botan

#if defined(BOTAN_TARGET_OS_HAS_THREADS)
   #include <thread>
#endif

namespace Botan::OS {

/*
* This header is internal (not installed) and these functions are not
* intended to be called by applications. However they are given public
* visibility (using BOTAN_TEST_API macro) for the tests. This also probably
* allows them to be overridden by the application on ELF systems, but
* this hasn't been tested.
*/

/**
* @return process ID assigned by the operating system.
*
* On Unix and Windows systems, this always returns a result
*
* On systems where there is no processes to speak of (for example on baremetal
* systems or within a unikernel), this function returns zero.
*/
uint32_t BOTAN_TEST_API get_process_id();

/**
* @return CPU processor clock, if available
*
* On Windows, calls QueryPerformanceCounter.
*
* Under GCC or Clang on supported platforms the hardware cycle counter is queried.
* Currently supported processors are x86, PPC, Alpha, SPARC, IA-64, S/390x, and HP-PA.
* If no CPU cycle counter is available on this system, returns zero.
*/
uint64_t BOTAN_TEST_API get_cpu_cycle_counter();

size_t BOTAN_TEST_API get_cpu_available();

/**
* If this system supports getauxval (or an equivalent interface,
* like FreeBSD's elf_aux_info) queries AT_HWCAP and AT_HWCAP2
* and returns both.
*
* Otherwise returns nullopt.
*/
std::optional<std::pair<unsigned long, unsigned long>> get_auxval_hwcap();

/*
* @return best resolution timestamp available
*
* The epoch and update rate of this clock is arbitrary and depending
* on the hardware it may not tick at a constant rate.
*
* Uses hardware cycle counter, if available.
* On POSIX platforms clock_gettime is used with a monotonic timer
*
* As a final fallback std::chrono::high_resolution_clock is used.
*
* On systems that are lacking a real time clock, this may return 0
*/
uint64_t BOTAN_TEST_API get_high_resolution_clock();

/**
* @return system clock (reflecting wall clock) with best resolution
* available, normalized to nanoseconds resolution, using Unix epoch.
*
* If the system does not have a real time clock this function will throw
* Not_Implemented
*/
uint64_t BOTAN_TEST_API get_system_timestamp_ns();

/**
* Format a time
*
* Converts the time_t to a local time representation,
* then invokes std::put_time with the specified format.
*/
std::string BOTAN_TEST_API format_time(time_t time, const std::string& format);

/**
* @return maximum amount of memory (in bytes) Botan could/should
* hypothetically allocate for the memory poool. Reads environment
* variable "BOTAN_MLOCK_POOL_SIZE", set to "0" to disable pool.
*/
size_t get_memory_locking_limit();

/**
* Return the size of a memory page, if that can be derived on the
* current system. Otherwise returns some default value (eg 4096)
*/
size_t system_page_size();

/**
* Read the value of an environment variable, setting it to value_out if it
* exists.  Returns false and sets value_out to empty string if no such variable
* is set. If the process seems to be running in a privileged state (such as
* setuid) then always returns false and does not examine the environment.
*/
bool read_env_variable(std::string& value_out, std::string_view var_name);

/**
* Read the value of an environment variable and convert it to an
* integer. If not set or conversion fails, returns the default value.
*
* If the process seems to be running in a privileged state (such as setuid)
* then always returns nullptr, similar to glibc's secure_getenv.
*/
size_t read_env_variable_sz(std::string_view var_name, size_t def_value = 0);

/**
* Request count pages of RAM which are locked into memory using mlock,
* VirtualLock, or some similar OS specific API. Free it with free_locked_pages.
*
* Returns an empty list on failure. This function is allowed to return fewer
* than count pages.
*
* The contents of the allocated pages are undefined.
*
* Each page is preceded by and followed by a page which is marked
* as noaccess, such that accessing it will cause a crash. This turns
* out of bound reads/writes into crash events.
*
* @param count requested number of locked pages
*/
std::vector<void*> allocate_locked_pages(size_t count);

/**
* Free memory allocated by allocate_locked_pages
* @param pages a list of pages returned by allocate_locked_pages
*/
void free_locked_pages(const std::vector<void*>& pages);

/**
* Set the MMU to prohibit access to this page
*/
void page_prohibit_access(void* page);

/**
* Set the MMU to allow R/W access to this page
*/
void page_allow_access(void* page);

/**
* Set a ID to a page's range expressed by size bytes
*/
void page_named(void* page, size_t size);

#if defined(BOTAN_TARGET_OS_HAS_THREADS)
void set_thread_name(std::thread& thread, const std::string& name);
#endif

/**
* Run a probe instruction to test for support for a CPU instruction.
* Runs in system-specific env that catches illegal instructions; this
* function always fails if the OS doesn't provide this.
* Returns value of probe_fn, if it could run.
* If error occurs, returns negative number.
* This allows probe_fn to indicate errors of its own, if it wants.
* For example the instruction might not only be only available on some
* CPUs, but also buggy on some subset of these - the probe function
* can test to make sure the instruction works properly before
* indicating that the instruction is available.
*
* @warning on Unix systems uses signal handling in a way that is not
* thread safe. It should only be called in a single-threaded context
* (ie, at static init time).
*
* If probe_fn throws an exception the result is undefined.
*
* Return codes:
* -1 illegal instruction detected
*/
int BOTAN_TEST_API run_cpu_instruction_probe(const std::function<int()>& probe_fn);

/**
* Represents a terminal state
*/
class BOTAN_UNSTABLE_API Echo_Suppression /* NOLINT(*special-member-functions) */ {
   public:
      /**
      * Reenable echo on this terminal. Can be safely called
      * multiple times. May throw if an error occurs.
      */
      virtual void reenable_echo() = 0;

      /**
      * Implicitly calls reenable_echo, but swallows/ignored all
      * errors which would leave the terminal in an invalid state.
      */
      virtual ~Echo_Suppression() = default;
};

/**
* Suppress echo on the terminal
* Returns null if this operation is not supported on the current system.
*/
std::unique_ptr<Echo_Suppression> BOTAN_UNSTABLE_API suppress_echo_on_terminal();

}  // namespace Botan::OS

namespace Botan {

/**
* Parse a SCAN-style algorithm name
* @param scan_name the name
* @return the name components
*/
std::vector<std::string> parse_algorithm_name(std::string_view scan_name);

/**
* Split a string
* @param str the input string
* @param delim the delimiter
* @return string split by delim
*/
BOTAN_TEST_API std::vector<std::string> split_on(std::string_view str, char delim);

/**
* Join a string
* @param strs strings to join
* @param delim the delimiter
* @return string joined by delim
*/
std::string string_join(const std::vector<std::string>& strs, char delim);

/**
* Convert a decimal string to a number, throwing if invalid
* @param input the string to convert
* @return number value of the string
*/
BOTAN_TEST_API uint32_t to_u32bit(std::string_view input);

/**
* Attempt to parse a string as a 16-bit decimal integer
*
* @param input the string to convert
* @param require_canonical if set, reject leading zeros ("007"); "0" is still accepted
* @return integer value, or nullopt if invalid
*/
std::optional<uint16_t> parse_u16(std::string_view input, bool require_canonical = false);

/**
* Attempt to parse a string as a 32-bit decimal integer
*
* @param input the string to convert
* @param require_canonical if set, reject leading zeros ("007"); "0" is still accepted
* @return integer value, or nullopt if invalid
*/
BOTAN_TEST_API std::optional<uint32_t> parse_u32(std::string_view input, bool require_canonical = false);

/**
* Attempt to parse a string as a 64-bit decimal integer
*
* @param input the string to convert
* @param require_canonical if set, reject leading zeros ("007"); "0" is still accepted
* @return integer value, or nullopt if invalid
*/
BOTAN_TEST_API std::optional<uint64_t> parse_u64(std::string_view input, bool require_canonical = false);

/**
* Attempt to parse a string as a size_t-sized decimal integer
*
* @param input the string to convert
* @param require_canonical if set, reject leading zeros ("007"); "0" is still accepted
* @return integer value, or nullopt if invalid
*/
BOTAN_TEST_API std::optional<size_t> parse_sz(std::string_view input, bool require_canonical = false);

std::map<std::string, std::string> read_cfg(std::istream& is);

/**
* Accepts key value pairs delimited by commas:
*
* "" (returns empty map)
* "K=V" (returns map {'K': 'V'})
* "K1=V1,K2=V2"
* "K1=V1,K2=V2,K3=V3"
* "K1=V1,K2=V2,K3=a_value\,with\,commas_and_\=equals"
*
* Values may be empty, keys must be non-empty and unique. Duplicate
* keys cause an exception.
*
* Within both key and value, comma and equals can be escaped with
* backslash. Backslash can also be escaped.
*/
BOTAN_TEST_API
std::map<std::string, std::string> read_kv(std::string_view kv);

std::string tolower_string(std::string_view str);

}  // namespace Botan

namespace Botan {

/**
* DJB's Poly1305
* Important note: each key can only be used once
*/
class Poly1305 final : public MessageAuthenticationCode {
   public:
      std::string name() const override { return "Poly1305"; }

      std::string provider() const override;

      std::unique_ptr<MessageAuthenticationCode> new_object() const override { return std::make_unique<Poly1305>(); }

      void clear() override;

      size_t output_length() const override { return 16; }

      Key_Length_Specification key_spec() const override { return Key_Length_Specification(32); }

      bool fresh_key_required_per_message() const override { return true; }

      bool has_keying_material() const override;

   private:
      void add_data(std::span<const uint8_t> input) override;
      void final_result(std::span<uint8_t> output) override;
      void start_msg(std::span<const uint8_t> nonce) override;
      void key_schedule(std::span<const uint8_t> key) override;

#if defined(BOTAN_HAS_POLY1305_AVX2)
      static size_t poly1305_avx2_blocks(secure_vector<uint64_t>& X, const uint8_t m[], size_t blocks);
#endif

#if defined(BOTAN_HAS_POLY1305_AVX512)
      static size_t poly1305_avx512_blocks(secure_vector<uint64_t>& X, const uint8_t m[], size_t blocks);
#endif

      // State layout: pad [2] || accum [3] || r [3] || r^2 [3] || ... || r^n [3]
      secure_vector<uint64_t> m_poly;
      AlignmentBuffer<uint8_t, 16> m_buffer;
};

}  // namespace Botan

namespace Botan {

/**
* Prefetch an array
*
* This function returns a uint64_t which is accumulated from values
* read from the array. This may help confuse the compiler sufficiently
* to not elide otherwise "useless" reads. The return value will always
* be zero.
*/
uint64_t prefetch_array_raw(size_t bytes, const void* array) noexcept;

/**
* Prefetch several arrays
*
* This function returns a uint64_t which is accumulated from values
* read from the array. This may help confuse the compiler sufficiently
* to not elide otherwise "useless" reads. The return value will always
* be zero.
*/
template <std::unsigned_integral T, size_t... Ns>
T prefetch_arrays(T (&... arr)[Ns]) noexcept {
   return (static_cast<T>(prefetch_array_raw(sizeof(T) * Ns, arr)) & ...);
}

}  // namespace Botan

namespace Botan {

/**
* Bit rotation left by a compile-time constant amount
* @param input the input word
* @return input rotated left by ROT bits
*/
template <size_t ROT, std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T rotl(T input)
   requires(ROT > 0 && ROT < 8 * sizeof(T))
{
   return static_cast<T>((input << ROT) | (input >> (8 * sizeof(T) - ROT)));
}

/**
* Bit rotation right by a compile-time constant amount
* @param input the input word
* @return input rotated right by ROT bits
*/
template <size_t ROT, std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T rotr(T input)
   requires(ROT > 0 && ROT < 8 * sizeof(T))
{
   return static_cast<T>((input >> ROT) | (input << (8 * sizeof(T) - ROT)));
}

/**
* SHA-2 Sigma style function
*/
template <size_t R1, size_t R2, size_t S, std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T sigma(T x) {
   return rotr<R1>(x) ^ rotr<R2>(x) ^ (x >> S);
}

/**
* SHA-2 Sigma style function
*/
template <size_t R1, size_t R2, size_t R3, std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T rho(T x) {
   return rotr<R1>(x) ^ rotr<R2>(x) ^ rotr<R3>(x);
}

/**
* Bit rotation left, variable rotation amount
* @param input the input word
* @param rot the number of bits to rotate, must be between 0 and sizeof(T)*8-1
* @return input rotated left by rot bits
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T rotl_var(T input, size_t rot) {
   return rot ? static_cast<T>((input << rot) | (input >> (sizeof(T) * 8 - rot))) : input;
}

/**
* Bit rotation right, variable rotation amount
* @param input the input word
* @param rot the number of bits to rotate, must be between 0 and sizeof(T)*8-1
* @return input rotated right by rot bits
*/
template <std::unsigned_integral T>
BOTAN_FORCE_INLINE constexpr T rotr_var(T input, size_t rot) {
   return rot ? static_cast<T>((input >> rot) | (input << (sizeof(T) * 8 - rot))) : input;
}

}  // namespace Botan

namespace Botan {

/**
* Integer rounding
*
* Returns an integer z such that n <= z <= n + align_to
* and z % align_to == 0
*
* @param n an integer
* @param align_to the alignment boundary
* @return n rounded up to a multiple of align_to
*/
constexpr inline size_t round_up(size_t n, size_t align_to) {
   // Arguably returning n in this case would also be sensible
   BOTAN_ARG_CHECK(align_to != 0, "align_to must not be 0");

   if(n % align_to > 0) {
      const size_t adj = align_to - (n % align_to);
      BOTAN_ARG_CHECK(n + adj >= n, "Integer overflow during rounding");
      n += adj;
   }
   return n;
}

}  // namespace Botan

namespace Botan {

/**
A class encapsulating a SCAN name (similar to JCE conventions)
http://www.users.zetnet.co.uk/hopwood/crypto/scan/
*/
class BOTAN_TEST_API SCAN_Name final {
   public:
      /**
      * Create a SCAN_Name
      * @param algo_spec A SCAN-format name
      */
      explicit SCAN_Name(std::string_view algo_spec);

      /**
      * @return original input string
      */
      const std::string& to_string() const { return m_orig_algo_spec; }

      /**
      * @return algorithm name
      */
      const std::string& algo_name() const { return m_alg_name; }

      /**
      * @return number of arguments
      */
      size_t arg_count() const { return m_args.size(); }

      /**
      * @param lower is the lower bound
      * @param upper is the upper bound
      * @return if the number of arguments is between lower and upper
      */
      bool arg_count_between(size_t lower, size_t upper) const {
         return ((arg_count() >= lower) && (arg_count() <= upper));
      }

      /**
      * @param i which argument
      * @return ith argument
      */
      std::string arg(size_t i) const;

      /**
      * @param i which argument
      * @param def_value the default value
      * @return ith argument or the default value
      */
      std::string arg(size_t i, std::string_view def_value) const;

      /**
      * @param i which argument
      * @param def_value the default value
      * @return ith argument as an integer, or the default value
      */
      size_t arg_as_integer(size_t i, size_t def_value) const;

      /**
      * @param i which argument
      * @return ith argument as an integer
      */
      size_t arg_as_integer(size_t i) const;

      /**
      * @return cipher mode (if any)
      */
      std::string cipher_mode() const { return (!m_mode_info.empty()) ? m_mode_info[0] : ""; }

      /**
      * @return cipher mode padding (if any)
      */
      std::string cipher_mode_pad() const { return (m_mode_info.size() >= 2) ? m_mode_info[1] : ""; }

   private:
      std::string m_orig_algo_spec;
      std::string m_alg_name;
      std::vector<std::string> m_args;
      std::vector<std::string> m_mode_info;
};

// This is unrelated but it is convenient to stash it here
template <typename T>
std::vector<std::string> probe_providers_of(std::string_view algo_spec,
                                            const std::vector<std::string>& possible = {"base"}) {
   std::vector<std::string> providers;
   for(auto&& prov : possible) {
      auto o = T::create(algo_spec, prov);
      if(o) {
         providers.push_back(prov);  // available
      }
   }
   return providers;
}

}  // namespace Botan

namespace Botan {

/**
* SHA-224
*/
class SHA_224 final : public HashFunction {
   public:
      using digest_type = secure_vector<uint32_t>;

      static constexpr MD_Endian byte_endianness = MD_Endian::Big;
      static constexpr MD_Endian bit_endianness = MD_Endian::Big;
      static constexpr size_t block_bytes = 64;
      static constexpr size_t output_bytes = 28;
      static constexpr size_t ctr_bytes = 8;

      static void compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
      static void init(digest_type& digest);

   public:
      std::string name() const override { return "SHA-224"; }

      size_t output_length() const override { return output_bytes; }

      size_t hash_block_size() const override { return block_bytes; }

      std::unique_ptr<HashFunction> new_object() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

      void clear() override { m_md.clear(); }

      std::string provider() const override;

   private:
      void add_data(std::span<const uint8_t> input) override;

      void final_result(std::span<uint8_t> output) override;

   private:
      MerkleDamgard_Hash<SHA_224> m_md;
};

/**
* SHA-256
*/
class SHA_256 final : public HashFunction {
   public:
      using digest_type = secure_vector<uint32_t>;

      static constexpr MD_Endian byte_endianness = MD_Endian::Big;
      static constexpr MD_Endian bit_endianness = MD_Endian::Big;
      static constexpr size_t block_bytes = 64;
      static constexpr size_t output_bytes = 32;
      static constexpr size_t ctr_bytes = 8;

      static void compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
      static void init(digest_type& digest);

   public:
      std::string name() const override { return "SHA-256"; }

      size_t output_length() const override { return output_bytes; }

      size_t hash_block_size() const override { return block_bytes; }

      std::unique_ptr<HashFunction> new_object() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

      void clear() override { m_md.clear(); }

      std::string provider() const override;

   public:
      static void compress_digest(digest_type& digest, std::span<const uint8_t> input, size_t blocks);

#if defined(BOTAN_HAS_SHA2_32_ARMV8)
      static void compress_digest_armv8(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_32_SIMD)
      static void compress_digest_x86_simd(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_32_X86_AVX2)
      static void compress_digest_x86_avx2(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_32_X86)
      static void compress_digest_x86(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

   private:
      void add_data(std::span<const uint8_t> input) override;

      void final_result(std::span<uint8_t> output) override;

   private:
      MerkleDamgard_Hash<SHA_256> m_md;
};

}  // namespace Botan

namespace Botan {

/*
* SHA-256 F1 Function
*/
BOTAN_FORCE_INLINE void SHA2_32_F(uint32_t A,
                                  uint32_t B,
                                  uint32_t C,
                                  uint32_t& D,
                                  uint32_t E,
                                  uint32_t F,
                                  uint32_t G,
                                  uint32_t& H,
                                  uint32_t& M1,
                                  uint32_t M2,
                                  uint32_t M3,
                                  uint32_t M4,
                                  uint32_t magic) {
   H += magic + rho<6, 11, 25>(E) + choose(E, F, G) + M1;
   D += H;
   H += rho<2, 13, 22>(A) + majority(A, B, C);
   M1 += sigma<17, 19, 10>(M2) + M3 + sigma<7, 18, 3>(M4);
}

/*
* SHA-256 F1 Function (No Message Expansion)
*/
BOTAN_FORCE_INLINE void SHA2_32_F(
   uint32_t A, uint32_t B, uint32_t C, uint32_t& D, uint32_t E, uint32_t F, uint32_t G, uint32_t& H, uint32_t M) {
   H += rho<6, 11, 25>(E) + choose(E, F, G) + M;
   D += H;
   H += rho<2, 13, 22>(A) + majority(A, B, C);
}

}  // namespace Botan

namespace Botan {

/**
* SHA-384
*/
class SHA_384 final : public HashFunction {
   public:
      using digest_type = secure_vector<uint64_t>;

      static constexpr MD_Endian byte_endianness = MD_Endian::Big;
      static constexpr MD_Endian bit_endianness = MD_Endian::Big;
      static constexpr size_t block_bytes = 128;
      static constexpr size_t output_bytes = 48;
      static constexpr size_t ctr_bytes = 16;

      static void compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
      static void init(digest_type& digest);

   public:
      std::string name() const override { return "SHA-384"; }

      size_t output_length() const override { return output_bytes; }

      size_t hash_block_size() const override { return block_bytes; }

      std::unique_ptr<HashFunction> new_object() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

      std::string provider() const override;

      void clear() override { m_md.clear(); }

   private:
      void add_data(std::span<const uint8_t> input) override;

      void final_result(std::span<uint8_t> output) override;

   private:
      MerkleDamgard_Hash<SHA_384> m_md;
};

/**
* SHA-512
*/
class SHA_512 final : public HashFunction {
   public:
      using digest_type = secure_vector<uint64_t>;

      static constexpr MD_Endian byte_endianness = MD_Endian::Big;
      static constexpr MD_Endian bit_endianness = MD_Endian::Big;
      static constexpr size_t block_bytes = 128;
      static constexpr size_t output_bytes = 64;
      static constexpr size_t ctr_bytes = 16;

      static void compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
      static void init(digest_type& digest);

   public:
      std::string name() const override { return "SHA-512"; }

      size_t output_length() const override { return output_bytes; }

      size_t hash_block_size() const override { return block_bytes; }

      std::unique_ptr<HashFunction> new_object() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

      std::string provider() const override;

      void clear() override { m_md.clear(); }

   public:
      static void compress_digest(digest_type& digest, std::span<const uint8_t> input, size_t blocks);

#if defined(BOTAN_HAS_SHA2_64_X86_AVX2)
      static void compress_digest_x86_avx2(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_64_X86_AVX512)
      static void compress_digest_x86_avx512(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_64_X86)
      static void compress_digest_x86(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

#if defined(BOTAN_HAS_SHA2_64_ARMV8)
      static void compress_digest_armv8(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
#endif

   private:
      void add_data(std::span<const uint8_t> input) override;

      void final_result(std::span<uint8_t> output) override;

   private:
      MerkleDamgard_Hash<SHA_512> m_md;
};

/**
* SHA-512/256
*/
class SHA_512_256 final : public HashFunction {
   public:
      using digest_type = secure_vector<uint64_t>;

      static constexpr MD_Endian byte_endianness = MD_Endian::Big;
      static constexpr MD_Endian bit_endianness = MD_Endian::Big;
      static constexpr size_t block_bytes = 128;
      static constexpr size_t output_bytes = 32;
      static constexpr size_t ctr_bytes = 16;

      static void compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks);
      static void init(digest_type& digest);

   public:
      std::string name() const override { return "SHA-512-256"; }

      size_t output_length() const override { return output_bytes; }

      size_t hash_block_size() const override { return block_bytes; }

      std::unique_ptr<HashFunction> new_object() const override;

      std::unique_ptr<HashFunction> copy_state() const override;

      std::string provider() const override;

      void clear() override { m_md.clear(); }

   private:
      void add_data(std::span<const uint8_t> input) override;

      void final_result(std::span<uint8_t> output) override;

   private:
      MerkleDamgard_Hash<SHA_512_256> m_md;
};

}  // namespace Botan

namespace Botan {

/*
* SHA-512 F1 Function
*/
BOTAN_FORCE_INLINE void SHA2_64_F(uint64_t A,
                                  uint64_t B,
                                  uint64_t C,
                                  uint64_t& D,
                                  uint64_t E,
                                  uint64_t F,
                                  uint64_t G,
                                  uint64_t& H,
                                  uint64_t& M1,
                                  uint64_t M2,
                                  uint64_t M3,
                                  uint64_t M4,
                                  uint64_t magic) {
   H += magic + rho<14, 18, 41>(E) + choose(E, F, G) + M1;
   D += H;
   H += rho<28, 34, 39>(A) + majority(A, B, C);
   M1 += sigma<19, 61, 6>(M2) + M3 + sigma<1, 8, 7>(M4);
}

/*
* SHA-512 F1 Function (No Message Expansion)
*/
BOTAN_FORCE_INLINE void SHA2_64_F(
   uint64_t A, uint64_t B, uint64_t C, uint64_t& D, uint64_t E, uint64_t F, uint64_t G, uint64_t& H, uint64_t M) {
   H += rho<14, 18, 41>(E) + choose(E, F, G) + M;
   D += H;
   H += rho<28, 34, 39>(A) + majority(A, B, C);
}

}  // namespace Botan

// TODO(Botan4): Move this to compiler.h (currently still a public header)

#if !defined(BOTAN_SCRUB_STACK_AFTER_RETURN)
   #if BOTAN_COMPILER_HAS_ATTRIBUTE(strub) && defined(BOTAN_USE_COMPILER_ASSISTED_STACK_SCRUBBING)
      /**
      * When a function definition is annotated with this macro, the compiler
      * generates a wrapper for the function's body to handle stack scrubbing
      * in the wrapper. In contrast to 'strub("at-calls")' this does not alter
      * the function's ABI.
      *
      * It is okay to use this annotation on C++ method definitions (in *.cpp),
      * even if the function is a public API.
      *
      * Currently this is supported on GCC 14+ only
      * See: https://gcc.gnu.org/onlinedocs/gcc-14.2.0/gcc/Common-Type-Attributes.html#index-strub-type-attribute
      */
      #define BOTAN_SCRUB_STACK_AFTER_RETURN BOTAN_COMPILER_ATTRIBUTE(strub("internal"))
   #else
      #define BOTAN_SCRUB_STACK_AFTER_RETURN
   #endif
#endif

namespace Botan {

/**
 * Reduce the values of @p keys into an accumulator initialized with @p acc using
 * the reducer function @p reducer.
 *
 * The @p reducer is a function taking the accumulator and a single key to return the
 * new accumulator. Keys are consecutively reduced into the accumulator.
 *
 * @return the accumulator containing the reduction of @p keys
 */
template <typename RetT, typename KeyT, typename ReducerT>
RetT reduce(const std::vector<KeyT>& keys, RetT acc, ReducerT reducer)
   requires std::invocable<ReducerT&, RetT, const KeyT&> &&
            std::convertible_to<std::invoke_result_t<ReducerT&, RetT, const KeyT&>, RetT>
{
   for(const KeyT& key : keys) {
      acc = reducer(std::move(acc), key);
   }
   return acc;
}

/**
* Existence check for values
*/
template <typename T, typename V>
bool value_exists(const std::vector<T>& vec, const V& val) {
   for(const auto& elem : vec) {
      if(elem == val) {
         return true;
      }
   }
   return false;
}

template <typename T, typename Pred>
void map_remove_if(Pred pred, T& assoc) {
   auto i = assoc.begin();
   while(i != assoc.end()) {
      if(pred(i->first)) {
         assoc.erase(i++);
      } else {
         i++;
      }
   }
}

template <typename... Alts, typename... Ts>
constexpr bool holds_any_of(const std::variant<Ts...>& v) noexcept {
   return (std::holds_alternative<Alts>(v) || ...);
}

template <typename GeneralVariantT, typename SpecialT>
constexpr bool is_generalizable_to(const SpecialT& /*unnamed*/) noexcept {
   return std::is_constructible_v<GeneralVariantT, SpecialT>;
}

template <typename GeneralVariantT, typename... SpecialTs>
constexpr bool is_generalizable_to(const std::variant<SpecialTs...>& /*unnamed*/) noexcept {
   return (std::is_constructible_v<GeneralVariantT, SpecialTs> && ...);
}

/**
 * @brief Converts a given variant into another variant-ish whose type states
 *        are a super set of the given variant.
 *
 * This is useful to convert restricted variant types into more general
 * variants types.
 */
template <typename GeneralVariantT, typename SpecialT>
constexpr GeneralVariantT generalize_to(SpecialT&& specific)
   requires(std::is_constructible_v<GeneralVariantT, std::decay_t<SpecialT>>)
{
   return std::forward<SpecialT>(specific);
}

/**
 * @brief Converts a given variant into another variant-ish whose type states
 *        are a super set of the given variant.
 *
 * This is useful to convert restricted variant types into more general
 * variants types.
 */
template <typename GeneralVariantT, typename... SpecialTs>
constexpr GeneralVariantT generalize_to(std::variant<SpecialTs...> specific) {
   static_assert(
      is_generalizable_to<GeneralVariantT>(specific),
      "Desired general type must be implicitly constructible by all types of the specialized std::variant<>");
   return std::visit([](auto s) -> GeneralVariantT { return s; }, std::move(specific));
}

/**
 * @brief Converts a given variant into another variant whose type states
 *        are a subset of the given variant.
 *
 * @returns a variant of type SpecificVariantT if the given variant holds a
 *          type in SpecificVariantT, std::nullopt otherwise.
 */
template <typename SpecificVariantT, typename GeneralVariantT>
constexpr std::optional<SpecificVariantT> specialize_to(GeneralVariantT&& v) {
   return std::visit(
      []<typename AlternativeT>(AlternativeT&& obj) -> std::optional<SpecificVariantT> {
         if constexpr(std::is_constructible_v<SpecificVariantT, AlternativeT>) {
            return std::forward<AlternativeT>(obj);
         } else {
            return std::nullopt;
         }
      },
      std::forward<GeneralVariantT>(v));
}

// This is a helper utility to emulate pattern matching with std::visit.
// See https://en.cppreference.com/w/cpp/utility/variant/visit for more info.
template <class... Ts>
struct overloaded : Ts... {
      using Ts::operator()...;
};
// explicit deduction guide (not needed as of C++20)
template <class... Ts>
overloaded(Ts...) -> overloaded<Ts...>;

// TODO: C++23: replace with std::to_underlying
template <typename T>
   requires std::is_enum_v<T>
auto to_underlying(T e) noexcept {
   return static_cast<std::underlying_type_t<T>>(e);
}

// TODO: C++23 - use std::out_ptr
template <typename T>
[[nodiscard]] constexpr auto out_ptr(T& outptr) noexcept {
   class out_ptr_t {
      public:
         constexpr ~out_ptr_t() noexcept {
            m_ptr.reset(m_rawptr);
            m_rawptr = nullptr;
         }

         constexpr explicit out_ptr_t(T& outptr) noexcept : m_ptr(outptr), m_rawptr(nullptr) {}

         out_ptr_t(const out_ptr_t&) = delete;
         out_ptr_t(out_ptr_t&&) = delete;
         out_ptr_t& operator=(const out_ptr_t&) = delete;
         out_ptr_t& operator=(out_ptr_t&&) = delete;

         // NOLINTNEXTLINE(*-explicit-conversions) - Implicit by design for C API interop
         [[nodiscard]] constexpr operator typename T::element_type **() && noexcept { return &m_rawptr; }

      private:
         T& m_ptr;
         typename T::element_type* m_rawptr;
   };

   return out_ptr_t{outptr};
}

}  // namespace Botan


#if defined(BOTAN_HAS_STREAM_CIPHER)
#endif

namespace Botan {

#if defined(BOTAN_HAS_STREAM_CIPHER)

class Stream_Cipher_Mode final : public Cipher_Mode {
   public:
      /**
      * @param cipher underlying stream cipher
      */
      explicit Stream_Cipher_Mode(std::unique_ptr<StreamCipher> cipher) : m_cipher(std::move(cipher)) {}

      size_t output_length(size_t input_length) const override { return input_length; }

      size_t update_granularity() const override { return 1; }

      size_t ideal_granularity() const override {
         const size_t buf_size = m_cipher->buffer_size();
         BOTAN_ASSERT_NOMSG(buf_size > 0);
         if(buf_size >= 256) {
            return buf_size;
         }
         return buf_size * (256 / buf_size);
      }

      size_t minimum_final_size() const override { return 0; }

      size_t default_nonce_length() const override { return 0; }

      bool valid_nonce_length(size_t nonce_len) const override { return m_cipher->valid_iv_length(nonce_len); }

      Key_Length_Specification key_spec() const override { return m_cipher->key_spec(); }

      std::string name() const override { return m_cipher->name(); }

      void clear() override {
         m_cipher->clear();
         reset();
      }

      void reset() override { /* no msg state */
      }

      bool has_keying_material() const override { return m_cipher->has_keying_material(); }

   private:
      void start_msg(const uint8_t nonce[], size_t nonce_len) override {
         if(nonce_len > 0) {
            m_cipher->set_iv(nonce, nonce_len);
         }
      }

      size_t process_msg(uint8_t buf[], size_t sz) override {
         m_cipher->cipher1(buf, sz);
         return sz;
      }

      void finish_msg(secure_vector<uint8_t>& buf, size_t offset) override { return update(buf, offset); }

      void key_schedule(std::span<const uint8_t> key) override { m_cipher->set_key(key); }

      std::unique_ptr<StreamCipher> m_cipher;
};

#endif

}  // namespace Botan

#if defined(BOTAN_HAS_OS_UTILS)
#endif

namespace Botan {

template <typename F>
uint64_t measure_cost(uint64_t trial_msec, F func) {
#if defined(BOTAN_HAS_OS_UTILS)
   const uint64_t trial_nsec = trial_msec * 1000000;

   uint64_t total_nsec = 0;
   uint64_t trials = 0;

   auto trial_start = OS::get_system_timestamp_ns();

   for(;;) {
      const auto start = OS::get_system_timestamp_ns();
      func();
      const auto end = OS::get_system_timestamp_ns();

      if(end >= start) {
         total_nsec += (end - start);
         trials += 1;

         if((end - trial_start) >= trial_nsec) {
            return (total_nsec / trials);
         }
      }
   }

#else
   BOTAN_UNUSED(trial_msec, func);
   throw Not_Implemented("No system clock available");
#endif
}

}  // namespace Botan
/* NOLINTBEGIN(*-macro-usage) */

#define BOTAN_FULL_VERSION_STRING "Botan 3.13.0 (unreleased, revision git:2a81eef56c96c237e590c27f9a75e60317c9c700)"

#define BOTAN_SHORT_VERSION_STRING "3.13.0"

#define BOTAN_VC_REVISION "git:2a81eef56c96c237e590c27f9a75e60317c9c700"


/* NOLINTEND(*-macro-usage) */
/*
* (C) 2013,2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <sstream>

#if defined(BOTAN_HAS_BLOCK_CIPHER)
#endif

#if defined(BOTAN_HAS_AEAD_CCM)
#endif

#if defined(BOTAN_HAS_AEAD_CHACHA20_POLY1305)
#endif

#if defined(BOTAN_HAS_AEAD_EAX)
#endif

#if defined(BOTAN_HAS_AEAD_GCM)
#endif

#if defined(BOTAN_HAS_AEAD_GCM_SIV)
#endif

#if defined(BOTAN_HAS_AEAD_OCB)
#endif

#if defined(BOTAN_HAS_AEAD_SIV)
#endif

#if defined(BOTAN_HAS_ASCON_AEAD128)
#endif

namespace Botan {

std::unique_ptr<AEAD_Mode> AEAD_Mode::create_or_throw(std::string_view algo,
                                                      Cipher_Dir dir,
                                                      std::string_view provider) {
   if(auto aead = AEAD_Mode::create(algo, dir, provider)) {
      return aead;
   }

   throw Lookup_Error("AEAD", algo, provider);
}

std::unique_ptr<AEAD_Mode> AEAD_Mode::create(std::string_view algo, Cipher_Dir dir, std::string_view provider) {
   BOTAN_UNUSED(provider);
#if defined(BOTAN_HAS_AEAD_CHACHA20_POLY1305)
   if(algo == "ChaCha20Poly1305") {
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<ChaCha20Poly1305_Encryption>();
      } else {
         return std::make_unique<ChaCha20Poly1305_Decryption>();
      }
   }
#endif

#if defined(BOTAN_HAS_ASCON_AEAD128)
   if(algo == "Ascon-AEAD128") {
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<Ascon_AEAD128_Encryption>();
      } else {
         return std::make_unique<Ascon_AEAD128_Decryption>();
      }
   }
#endif

   if(algo.find('/') != std::string::npos) {
      const std::vector<std::string> algo_parts = split_on(algo, '/');
      if(algo_parts.size() < 2) {
         return std::unique_ptr<AEAD_Mode>();
      }
      const std::string_view cipher_name = algo_parts[0];
      const std::vector<std::string> mode_info = parse_algorithm_name(algo_parts[1]);

      if(mode_info.empty()) {
         return std::unique_ptr<AEAD_Mode>();
      }

      std::ostringstream mode_name;

      mode_name << mode_info[0] << '(' << cipher_name;
      for(size_t i = 1; i < mode_info.size(); ++i) {
         mode_name << ',' << mode_info[i];
      }
      for(size_t i = 2; i < algo_parts.size(); ++i) {
         mode_name << ',' << algo_parts[i];
      }
      mode_name << ')';

      return AEAD_Mode::create(mode_name.str(), dir);
   }

#if defined(BOTAN_HAS_BLOCK_CIPHER)

   const SCAN_Name req(algo);

   if(req.arg_count() == 0) {
      return std::unique_ptr<AEAD_Mode>();
   }

   auto bc = BlockCipher::create(req.arg(0), provider);

   if(!bc) {
      return std::unique_ptr<AEAD_Mode>();
   }

   #if defined(BOTAN_HAS_AEAD_CCM)
   if(req.algo_name() == "CCM") {
      const size_t tag_len = req.arg_as_integer(1, 16);
      const size_t L_len = req.arg_as_integer(2, 3);
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<CCM_Encryption>(std::move(bc), tag_len, L_len);
      } else {
         return std::make_unique<CCM_Decryption>(std::move(bc), tag_len, L_len);
      }
   }
   #endif

   #if defined(BOTAN_HAS_AEAD_GCM)
   if(req.algo_name() == "GCM") {
      const size_t tag_len = req.arg_as_integer(1, 16);
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<GCM_Encryption>(std::move(bc), tag_len);
      } else {
         return std::make_unique<GCM_Decryption>(std::move(bc), tag_len);
      }
   }
   #endif

   #if defined(BOTAN_HAS_AEAD_GCM_SIV)
   if(req.algo_name() == "GCM-SIV") {
      // Unlike GCM the tag length is fixed, so reject eg "AES-128/GCM-SIV(12)"
      if(req.arg_count() != 1) {
         return std::unique_ptr<AEAD_Mode>();
      }
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<GCM_SIV_Encryption>(std::move(bc));
      } else {
         return std::make_unique<GCM_SIV_Decryption>(std::move(bc));
      }
   }
   #endif

   #if defined(BOTAN_HAS_AEAD_OCB)
   if(req.algo_name() == "OCB") {
      const size_t tag_len = req.arg_as_integer(1, 16);
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<OCB_Encryption>(std::move(bc), tag_len);
      } else {
         return std::make_unique<OCB_Decryption>(std::move(bc), tag_len);
      }
   }
   #endif

   #if defined(BOTAN_HAS_AEAD_EAX)
   if(req.algo_name() == "EAX") {
      const size_t tag_len = req.arg_as_integer(1, bc->block_size());
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<EAX_Encryption>(std::move(bc), tag_len);
      } else {
         return std::make_unique<EAX_Decryption>(std::move(bc), tag_len);
      }
   }
   #endif

   #if defined(BOTAN_HAS_AEAD_SIV)
   if(req.algo_name() == "SIV") {
      if(dir == Cipher_Dir::Encryption) {
         return std::make_unique<SIV_Encryption>(std::move(bc));
      } else {
         return std::make_unique<SIV_Decryption>(std::move(bc));
      }
   }
   #endif

#endif

   return std::unique_ptr<AEAD_Mode>();
}

}  // namespace Botan
/*
* (C) 1999-2010,2015,2017,2018,2020 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

#if defined(BOTAN_HAS_AES_POWER8) || defined(BOTAN_HAS_AES_ARMV8) || defined(BOTAN_HAS_AES_NI)
   #define BOTAN_HAS_HW_AES_SUPPORT
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   #include <bit>
#endif

namespace Botan {

/*
* One of three AES implementation strategies are used to get a constant time
* implementation which is immune to common cache/timing based side channels:
*
* - If AES hardware support is available (AES-NI, POWER8, Aarch64) use that
*
* - If 128-bit SIMD with byte shuffles are available (SSSE3, NEON, or Altivec),
*   use the vperm technique published by Mike Hamburg at CHES 2009.
*
* - If no hardware or SIMD support, fall back to a constant time bitsliced
*   implementation. This uses 32-bit words resulting in 2 blocks being processed
*   in parallel. Moving to 4 blocks (with 64-bit words) would approximately
*   double performance on 64-bit CPUs. Likewise moving to 128 bit SIMD would
*   again approximately double performance vs 64-bit. However the assumption is
*   that most 64-bit CPUs either have hardware AES or SIMD shuffle support and
*   that the majority of users falling back to this code will be 32-bit cores.
*   If this assumption proves to be unsound, the bitsliced code can easily be
*   extended to operate on either 32 or 64 bit words depending on the native
*   wordsize of the target processor.
*
* Useful references
*
* - "Accelerating AES with Vector Permute Instructions" Mike Hamburg
*   https://www.shiftleft.org/papers/vector_aes/vector_aes.pdf
*
* - "Faster and Timing-Attack Resistant AES-GCM" Käsper and Schwabe
*   https://eprint.iacr.org/2009/129.pdf
*
* - "A new combinational logic minimization technique with applications to cryptology."
*   Boyar and Peralta https://eprint.iacr.org/2009/191.pdf
*
* - "A depth-16 circuit for the AES S-box" Boyar and Peralta
*    https://eprint.iacr.org/2011/332.pdf
*
* - "A Very Compact S-box for AES" Canright
*   https://www.iacr.org/archive/ches2005/032.pdf
*   https://core.ac.uk/download/pdf/36694529.pdf (extended)
*/

namespace {

/*
This is an AES sbox circuit which can execute in bitsliced mode up to 32x in
parallel.

The circuit is from the "Circuit Minimization Team" group
http://www.cs.yale.edu/homes/peralta/CircuitStuff/CMT.html
http://www.cs.yale.edu/homes/peralta/CircuitStuff/SLP_AES_113.txt

This circuit has size 113 and depth 27. In software it is much faster than
circuits which are considered faster for hardware purposes (where circuit depth
is the critical constraint), because unlike in hardware, on common CPUs we can
only execute - at best - 3 or 4 logic operations per cycle. So a smaller circuit
is superior. On an x86-64 machine this circuit is about 15% faster than the
circuit of size 128 and depth 16 given in "A depth-16 circuit for the AES S-box".

Another circuit for AES Sbox of size 102 and depth 24 is describted in "New
Circuit Minimization Techniques for Smaller and Faster AES SBoxes"
[https://eprint.iacr.org/2019/802] however it relies on "non-standard" gates
like MUX, NOR, NAND, etc and so in practice in bitsliced software, its size is
actually a bit larger than this circuit, as few CPUs have such instructions and
otherwise they must be emulated using a sequence of available bit operations.
*/
void AES_SBOX(uint32_t V[8]) {
   const uint32_t U0 = V[0];
   const uint32_t U1 = V[1];
   const uint32_t U2 = V[2];
   const uint32_t U3 = V[3];
   const uint32_t U4 = V[4];
   const uint32_t U5 = V[5];
   const uint32_t U6 = V[6];
   const uint32_t U7 = V[7];

   const uint32_t y14 = U3 ^ U5;
   const uint32_t y13 = U0 ^ U6;
   const uint32_t y9 = U0 ^ U3;
   const uint32_t y8 = U0 ^ U5;
   const uint32_t t0 = U1 ^ U2;
   const uint32_t y1 = t0 ^ U7;
   const uint32_t y4 = y1 ^ U3;
   const uint32_t y12 = y13 ^ y14;
   const uint32_t y2 = y1 ^ U0;
   const uint32_t y5 = y1 ^ U6;
   const uint32_t y3 = y5 ^ y8;
   const uint32_t t1 = U4 ^ y12;
   const uint32_t y15 = t1 ^ U5;
   const uint32_t y20 = t1 ^ U1;
   const uint32_t y6 = y15 ^ U7;
   const uint32_t y10 = y15 ^ t0;
   const uint32_t y11 = y20 ^ y9;
   const uint32_t y7 = U7 ^ y11;
   const uint32_t y17 = y10 ^ y11;
   const uint32_t y19 = y10 ^ y8;
   const uint32_t y16 = t0 ^ y11;
   const uint32_t y21 = y13 ^ y16;
   const uint32_t y18 = U0 ^ y16;
   const uint32_t t2 = y12 & y15;
   const uint32_t t3 = y3 & y6;
   const uint32_t t4 = t3 ^ t2;
   const uint32_t t5 = y4 & U7;
   const uint32_t t6 = t5 ^ t2;
   const uint32_t t7 = y13 & y16;
   const uint32_t t8 = y5 & y1;
   const uint32_t t9 = t8 ^ t7;
   const uint32_t t10 = y2 & y7;
   const uint32_t t11 = t10 ^ t7;
   const uint32_t t12 = y9 & y11;
   const uint32_t t13 = y14 & y17;
   const uint32_t t14 = t13 ^ t12;
   const uint32_t t15 = y8 & y10;
   const uint32_t t16 = t15 ^ t12;
   const uint32_t t17 = t4 ^ y20;
   const uint32_t t18 = t6 ^ t16;
   const uint32_t t19 = t9 ^ t14;
   const uint32_t t20 = t11 ^ t16;
   const uint32_t t21 = t17 ^ t14;
   const uint32_t t22 = t18 ^ y19;
   const uint32_t t23 = t19 ^ y21;
   const uint32_t t24 = t20 ^ y18;
   const uint32_t t25 = t21 ^ t22;
   const uint32_t t26 = t21 & t23;
   const uint32_t t27 = t24 ^ t26;
   const uint32_t t28 = t25 & t27;
   const uint32_t t29 = t28 ^ t22;
   const uint32_t t30 = t23 ^ t24;
   const uint32_t t31 = t22 ^ t26;
   const uint32_t t32 = t31 & t30;
   const uint32_t t33 = t32 ^ t24;
   const uint32_t t34 = t23 ^ t33;
   const uint32_t t35 = t27 ^ t33;
   const uint32_t t36 = t24 & t35;
   const uint32_t t37 = t36 ^ t34;
   const uint32_t t38 = t27 ^ t36;
   const uint32_t t39 = t29 & t38;
   const uint32_t t40 = t25 ^ t39;
   const uint32_t t41 = t40 ^ t37;
   const uint32_t t42 = t29 ^ t33;
   const uint32_t t43 = t29 ^ t40;
   const uint32_t t44 = t33 ^ t37;
   const uint32_t t45 = t42 ^ t41;
   const uint32_t z0 = t44 & y15;
   const uint32_t z1 = t37 & y6;
   const uint32_t z2 = t33 & U7;
   const uint32_t z3 = t43 & y16;
   const uint32_t z4 = t40 & y1;
   const uint32_t z5 = t29 & y7;
   const uint32_t z6 = t42 & y11;
   const uint32_t z7 = t45 & y17;
   const uint32_t z8 = t41 & y10;
   const uint32_t z9 = t44 & y12;
   const uint32_t z10 = t37 & y3;
   const uint32_t z11 = t33 & y4;
   const uint32_t z12 = t43 & y13;
   const uint32_t z13 = t40 & y5;
   const uint32_t z14 = t29 & y2;
   const uint32_t z15 = t42 & y9;
   const uint32_t z16 = t45 & y14;
   const uint32_t z17 = t41 & y8;
   const uint32_t tc1 = z15 ^ z16;
   const uint32_t tc2 = z10 ^ tc1;
   const uint32_t tc3 = z9 ^ tc2;
   const uint32_t tc4 = z0 ^ z2;
   const uint32_t tc5 = z1 ^ z0;
   const uint32_t tc6 = z3 ^ z4;
   const uint32_t tc7 = z12 ^ tc4;
   const uint32_t tc8 = z7 ^ tc6;
   const uint32_t tc9 = z8 ^ tc7;
   const uint32_t tc10 = tc8 ^ tc9;
   const uint32_t tc11 = tc6 ^ tc5;
   const uint32_t tc12 = z3 ^ z5;
   const uint32_t tc13 = z13 ^ tc1;
   const uint32_t tc14 = tc4 ^ tc12;
   const uint32_t S3 = tc3 ^ tc11;
   const uint32_t tc16 = z6 ^ tc8;
   const uint32_t tc17 = z14 ^ tc10;
   const uint32_t tc18 = ~tc13 ^ tc14;
   const uint32_t S7 = z12 ^ tc18;
   const uint32_t tc20 = z15 ^ tc16;
   const uint32_t tc21 = tc2 ^ z11;
   const uint32_t S0 = tc3 ^ tc16;
   const uint32_t S6 = tc10 ^ tc18;
   const uint32_t S4 = tc14 ^ S3;
   const uint32_t S1 = ~(S3 ^ tc16);
   const uint32_t tc26 = tc17 ^ tc20;
   const uint32_t S2 = ~(tc26 ^ z17);
   const uint32_t S5 = tc21 ^ tc17;

   V[0] = S0;
   V[1] = S1;
   V[2] = S2;
   V[3] = S3;
   V[4] = S4;
   V[5] = S5;
   V[6] = S6;
   V[7] = S7;
}

/*
A circuit for inverse AES Sbox of size 121 and depth 21 from
http://www.cs.yale.edu/homes/peralta/CircuitStuff/CMT.html
http://www.cs.yale.edu/homes/peralta/CircuitStuff/Sinv.txt
*/
void AES_INV_SBOX(uint32_t V[8]) {
   const uint32_t U0 = V[0];
   const uint32_t U1 = V[1];
   const uint32_t U2 = V[2];
   const uint32_t U3 = V[3];
   const uint32_t U4 = V[4];
   const uint32_t U5 = V[5];
   const uint32_t U6 = V[6];
   const uint32_t U7 = V[7];

   const uint32_t Y0 = U0 ^ U3;
   const uint32_t Y2 = ~(U1 ^ U3);
   const uint32_t Y4 = U0 ^ Y2;
   const uint32_t RTL0 = U6 ^ U7;
   const uint32_t Y1 = Y2 ^ RTL0;
   const uint32_t Y7 = ~(U2 ^ Y1);
   const uint32_t RTL1 = U3 ^ U4;
   const uint32_t Y6 = ~(U7 ^ RTL1);
   const uint32_t Y3 = Y1 ^ RTL1;
   const uint32_t RTL2 = ~(U0 ^ U2);
   const uint32_t Y5 = U5 ^ RTL2;
   const uint32_t sa1 = Y0 ^ Y2;
   const uint32_t sa0 = Y1 ^ Y3;
   const uint32_t sb1 = Y4 ^ Y6;
   const uint32_t sb0 = Y5 ^ Y7;
   const uint32_t ah = Y0 ^ Y1;
   const uint32_t al = Y2 ^ Y3;
   const uint32_t aa = sa0 ^ sa1;
   const uint32_t bh = Y4 ^ Y5;
   const uint32_t bl = Y6 ^ Y7;
   const uint32_t bb = sb0 ^ sb1;
   const uint32_t ab20 = sa0 ^ sb0;
   const uint32_t ab22 = al ^ bl;
   const uint32_t ab23 = Y3 ^ Y7;
   const uint32_t ab21 = sa1 ^ sb1;
   const uint32_t abcd1 = ah & bh;
   const uint32_t rr1 = Y0 & Y4;
   const uint32_t ph11 = ab20 ^ abcd1;
   const uint32_t t01 = Y1 & Y5;
   const uint32_t ph01 = t01 ^ abcd1;
   const uint32_t abcd2 = al & bl;
   const uint32_t r1 = Y2 & Y6;
   const uint32_t pl11 = ab22 ^ abcd2;
   const uint32_t r2 = Y3 & Y7;
   const uint32_t pl01 = r2 ^ abcd2;
   const uint32_t r3 = sa0 & sb0;
   const uint32_t vr1 = aa & bb;
   const uint32_t pr1 = vr1 ^ r3;
   const uint32_t wr1 = sa1 & sb1;
   const uint32_t qr1 = wr1 ^ r3;
   const uint32_t ab0 = ph11 ^ rr1;
   const uint32_t ab1 = ph01 ^ ab21;
   const uint32_t ab2 = pl11 ^ r1;
   const uint32_t ab3 = pl01 ^ qr1;
   const uint32_t cp1 = ab0 ^ pr1;
   const uint32_t cp2 = ab1 ^ qr1;
   const uint32_t cp3 = ab2 ^ pr1;
   const uint32_t cp4 = ab3 ^ ab23;
   const uint32_t tinv1 = cp3 ^ cp4;
   const uint32_t tinv2 = cp3 & cp1;
   const uint32_t tinv3 = cp2 ^ tinv2;
   const uint32_t tinv4 = cp1 ^ cp2;
   const uint32_t tinv5 = cp4 ^ tinv2;
   const uint32_t tinv6 = tinv5 & tinv4;
   const uint32_t tinv7 = tinv3 & tinv1;
   const uint32_t d2 = cp4 ^ tinv7;
   const uint32_t d0 = cp2 ^ tinv6;
   const uint32_t tinv8 = cp1 & cp4;
   const uint32_t tinv9 = tinv4 & tinv8;
   const uint32_t tinv10 = tinv4 ^ tinv2;
   const uint32_t d1 = tinv9 ^ tinv10;
   const uint32_t tinv11 = cp2 & cp3;
   const uint32_t tinv12 = tinv1 & tinv11;
   const uint32_t tinv13 = tinv1 ^ tinv2;
   const uint32_t d3 = tinv12 ^ tinv13;
   const uint32_t sd1 = d1 ^ d3;
   const uint32_t sd0 = d0 ^ d2;
   const uint32_t dl = d0 ^ d1;  // NOLINT(misc-confusable-identifiers)
   const uint32_t dh = d2 ^ d3;
   const uint32_t dd = sd0 ^ sd1;
   const uint32_t abcd3 = dh & bh;
   const uint32_t rr2 = d3 & Y4;
   const uint32_t t02 = d2 & Y5;
   const uint32_t abcd4 = dl & bl;
   const uint32_t r4 = d1 & Y6;
   const uint32_t r5 = d0 & Y7;
   const uint32_t r6 = sd0 & sb0;
   const uint32_t vr2 = dd & bb;
   const uint32_t wr2 = sd1 & sb1;
   const uint32_t abcd5 = dh & ah;
   const uint32_t r7 = d3 & Y0;
   const uint32_t r8 = d2 & Y1;
   const uint32_t abcd6 = dl & al;
   const uint32_t r9 = d1 & Y2;
   const uint32_t r10 = d0 & Y3;
   const uint32_t r11 = sd0 & sa0;
   const uint32_t vr3 = dd & aa;
   const uint32_t wr3 = sd1 & sa1;
   const uint32_t ph12 = rr2 ^ abcd3;
   const uint32_t ph02 = t02 ^ abcd3;
   const uint32_t pl12 = r4 ^ abcd4;
   const uint32_t pl02 = r5 ^ abcd4;
   const uint32_t pr2 = vr2 ^ r6;
   const uint32_t qr2 = wr2 ^ r6;
   const uint32_t p0 = ph12 ^ pr2;
   const uint32_t p1 = ph02 ^ qr2;
   const uint32_t p2 = pl12 ^ pr2;
   const uint32_t p3 = pl02 ^ qr2;
   const uint32_t ph13 = r7 ^ abcd5;
   const uint32_t ph03 = r8 ^ abcd5;
   const uint32_t pl13 = r9 ^ abcd6;
   const uint32_t pl03 = r10 ^ abcd6;
   const uint32_t pr3 = vr3 ^ r11;
   const uint32_t qr3 = wr3 ^ r11;
   const uint32_t p4 = ph13 ^ pr3;
   const uint32_t S7 = ph03 ^ qr3;
   const uint32_t p6 = pl13 ^ pr3;
   const uint32_t p7 = pl03 ^ qr3;
   const uint32_t S3 = p1 ^ p6;
   const uint32_t S6 = p2 ^ p6;
   const uint32_t S0 = p3 ^ p6;
   const uint32_t X11 = p0 ^ p2;
   const uint32_t S5 = S0 ^ X11;
   const uint32_t X13 = p4 ^ p7;
   const uint32_t X14 = X11 ^ X13;
   const uint32_t S1 = S3 ^ X14;
   const uint32_t X16 = p1 ^ S7;
   const uint32_t S2 = X14 ^ X16;
   const uint32_t X18 = p0 ^ p4;
   const uint32_t X19 = S5 ^ X16;
   const uint32_t S4 = X18 ^ X19;

   V[0] = S0;
   V[1] = S1;
   V[2] = S2;
   V[3] = S3;
   V[4] = S4;
   V[5] = S5;
   V[6] = S6;
   V[7] = S7;
}

inline void bit_transpose(uint32_t B[8]) {
   swap_bits<uint32_t>(B[1], B[0], 0x55555555, 1);
   swap_bits<uint32_t>(B[3], B[2], 0x55555555, 1);
   swap_bits<uint32_t>(B[5], B[4], 0x55555555, 1);
   swap_bits<uint32_t>(B[7], B[6], 0x55555555, 1);

   swap_bits<uint32_t>(B[2], B[0], 0x33333333, 2);
   swap_bits<uint32_t>(B[3], B[1], 0x33333333, 2);
   swap_bits<uint32_t>(B[6], B[4], 0x33333333, 2);
   swap_bits<uint32_t>(B[7], B[5], 0x33333333, 2);

   swap_bits<uint32_t>(B[4], B[0], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[5], B[1], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[6], B[2], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[7], B[3], 0x0F0F0F0F, 4);
}

inline void ks_expand(uint32_t B[8], const uint32_t K[], size_t r) {
   /*
   This is bit_transpose of K[r..r+4] || K[r..r+4], we can save some computation
   due to knowing the first and second halves are the same data.
   */
   for(size_t i = 0; i != 4; ++i) {
      B[i] = K[r + i];
   }

   swap_bits<uint32_t>(B[1], B[0], 0x55555555, 1);
   swap_bits<uint32_t>(B[3], B[2], 0x55555555, 1);

   swap_bits<uint32_t>(B[2], B[0], 0x33333333, 2);
   swap_bits<uint32_t>(B[3], B[1], 0x33333333, 2);

   B[4] = B[0];
   B[5] = B[1];
   B[6] = B[2];
   B[7] = B[3];

   swap_bits<uint32_t>(B[4], B[0], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[5], B[1], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[6], B[2], 0x0F0F0F0F, 4);
   swap_bits<uint32_t>(B[7], B[3], 0x0F0F0F0F, 4);
}

inline void shift_rows(uint32_t B[8]) {
   // 3 0 1 2 7 4 5 6 10 11 8 9 14 15 12 13 17 18 19 16 21 22 23 20 24 25 26 27 28 29 30 31
   if constexpr(HasNative64BitRegisters) {
      for(size_t i = 0; i != 8; i += 2) {
         uint64_t x = (static_cast<uint64_t>(B[i]) << 32) | B[i + 1];
         x = bit_permute_step<uint64_t>(x, 0x0022331100223311, 2);
         x = bit_permute_step<uint64_t>(x, 0x0055005500550055, 1);
         B[i] = static_cast<uint32_t>(x >> 32);
         B[i + 1] = static_cast<uint32_t>(x);
      }
   } else {
      for(size_t i = 0; i != 8; ++i) {
         uint32_t x = B[i];
         x = bit_permute_step<uint32_t>(x, 0x00223311, 2);
         x = bit_permute_step<uint32_t>(x, 0x00550055, 1);
         B[i] = x;
      }
   }
}

inline void inv_shift_rows(uint32_t B[8]) {
   // Inverse of shift_rows, just inverting the steps

   if constexpr(HasNative64BitRegisters) {
      for(size_t i = 0; i != 8; i += 2) {
         uint64_t x = (static_cast<uint64_t>(B[i]) << 32) | B[i + 1];
         x = bit_permute_step<uint64_t>(x, 0x0055005500550055, 1);
         x = bit_permute_step<uint64_t>(x, 0x0022331100223311, 2);
         B[i] = static_cast<uint32_t>(x >> 32);
         B[i + 1] = static_cast<uint32_t>(x);
      }
   } else {
      for(size_t i = 0; i != 8; ++i) {
         uint32_t x = B[i];
         x = bit_permute_step<uint32_t>(x, 0x00550055, 1);
         x = bit_permute_step<uint32_t>(x, 0x00223311, 2);
         B[i] = x;
      }
   }
}

inline void mix_columns(uint32_t B[8]) {
   // carry high bits in B[0] to positions in 0x1b == 0b11011
   const uint32_t X2[8] = {
      B[1],
      B[2],
      B[3],
      B[4] ^ B[0],
      B[5] ^ B[0],
      B[6],
      B[7] ^ B[0],
      B[0],
   };

   for(size_t i = 0; i != 8; i++) {
      const uint32_t X3 = B[i] ^ X2[i];
      B[i] = X2[i] ^ rotr<8>(B[i]) ^ rotr<16>(B[i]) ^ rotr<24>(X3);
   }
}

void inv_mix_columns(uint32_t B[8]) {
   /*
   OpenSSL's bsaes implementation credits Jussi Kivilinna with the lovely
   matrix decomposition

   | 0e 0b 0d 09 |   | 02 03 01 01 |   | 05 00 04 00 |
   | 09 0e 0b 0d | = | 01 02 03 01 | x | 00 05 00 04 |
   | 0d 09 0e 0b |   | 01 01 02 03 |   | 04 00 05 00 |
   | 0b 0d 09 0e |   | 03 01 01 02 |   | 00 04 00 05 |

   Notice the first component is simply the MixColumns matrix. So we can
   multiply first by (05,00,04,00) then perform MixColumns to get the equivalent
   of InvMixColumn.
   */
   const uint32_t X4[8] = {
      B[2],
      B[3],
      B[4] ^ B[0],
      B[5] ^ B[0] ^ B[1],
      B[6] ^ B[1],
      B[7] ^ B[0],
      B[0] ^ B[1],
      B[1],
   };

   for(size_t i = 0; i != 8; i++) {
      const uint32_t X5 = X4[i] ^ B[i];
      B[i] = X5 ^ rotr<16>(X4[i]);
   }

   mix_columns(B);
}

/*
* AES Encryption
*/
void aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks, const secure_vector<uint32_t>& EK) {
   BOTAN_ASSERT(EK.size() == 44 || EK.size() == 52 || EK.size() == 60, "Key was set");

   const size_t rounds = (EK.size() - 4) / 4;

   uint32_t KS[13 * 8] = {0};  // actual maximum is (rounds - 1) * 8
   for(size_t i = 0; i < rounds - 1; i += 1) {
      ks_expand(&KS[8 * i], EK.data(), 4 * i + 4);
   }

   const size_t BLOCK_SIZE = 16;
   const size_t BITSLICED_BLOCKS = 8 * sizeof(uint32_t) / BLOCK_SIZE;

   while(blocks > 0) {
      const size_t this_loop = std::min(blocks, BITSLICED_BLOCKS);

      uint32_t B[8] = {0};

      load_be(B, in, this_loop * 4);

      CT::poison(B, 8);

      for(size_t i = 0; i != 8; ++i) {
         B[i] ^= EK[i % 4];
      }

      bit_transpose(B);

      for(size_t r = 0; r != rounds - 1; ++r) {
         AES_SBOX(B);
         shift_rows(B);
         mix_columns(B);

         for(size_t i = 0; i != 8; ++i) {
            B[i] ^= KS[8 * r + i];
         }
      }

      // Final round:
      AES_SBOX(B);
      shift_rows(B);
      bit_transpose(B);

      for(size_t i = 0; i != 8; ++i) {
         B[i] ^= EK[4 * rounds + i % 4];
      }

      CT::unpoison(B, 8);

      copy_out_be(std::span(out, this_loop * 4 * sizeof(uint32_t)), B);

      in += this_loop * BLOCK_SIZE;
      out += this_loop * BLOCK_SIZE;
      blocks -= this_loop;
   }
}

/*
* AES Decryption
*/
void aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks, const secure_vector<uint32_t>& DK) {
   BOTAN_ASSERT(DK.size() == 44 || DK.size() == 52 || DK.size() == 60, "Key was set");

   const size_t rounds = (DK.size() - 4) / 4;

   uint32_t KS[13 * 8] = {0};  // actual maximum is (rounds - 1) * 8
   for(size_t i = 0; i < rounds - 1; i += 1) {
      ks_expand(&KS[8 * i], DK.data(), 4 * i + 4);
   }

   const size_t BLOCK_SIZE = 16;
   const size_t BITSLICED_BLOCKS = 8 * sizeof(uint32_t) / BLOCK_SIZE;

   while(blocks > 0) {
      const size_t this_loop = std::min(blocks, BITSLICED_BLOCKS);

      uint32_t B[8] = {0};

      load_be(B, in, this_loop * 4);

      CT::poison(B, 8);

      for(size_t i = 0; i != 8; ++i) {
         B[i] ^= DK[i % 4];
      }

      bit_transpose(B);

      for(size_t r = 0; r != rounds - 1; ++r) {
         AES_INV_SBOX(B);
         inv_shift_rows(B);
         inv_mix_columns(B);

         for(size_t i = 0; i != 8; ++i) {
            B[i] ^= KS[8 * r + i];
         }
      }

      // Final round:
      AES_INV_SBOX(B);
      inv_shift_rows(B);
      bit_transpose(B);

      for(size_t i = 0; i != 8; ++i) {
         B[i] ^= DK[4 * rounds + i % 4];
      }

      CT::unpoison(B, 8);

      copy_out_be(std::span(out, this_loop * 4 * sizeof(uint32_t)), B);

      in += this_loop * BLOCK_SIZE;
      out += this_loop * BLOCK_SIZE;
      blocks -= this_loop;
   }
}

inline uint32_t xtime32(uint32_t s) {
   const uint32_t lo_bit = 0x01010101;
   const uint32_t mask = 0x7F7F7F7F;
   const uint32_t poly = 0x1B;

   return ((s & mask) << 1) ^ (((s >> 7) & lo_bit) * poly);
}

inline uint32_t InvMixColumn(uint32_t s1) {
   const uint32_t s2 = xtime32(s1);
   const uint32_t s4 = xtime32(s2);
   const uint32_t s8 = xtime32(s4);
   const uint32_t s9 = s8 ^ s1;
   const uint32_t s11 = s9 ^ s2;
   const uint32_t s13 = s9 ^ s4;
   const uint32_t s14 = s8 ^ s4 ^ s2;

   return s14 ^ rotr<8>(s9) ^ rotr<16>(s13) ^ rotr<24>(s11);
}

void InvMixColumn_x4(uint32_t x[4]) {
   x[0] = InvMixColumn(x[0]);
   x[1] = InvMixColumn(x[1]);
   x[2] = InvMixColumn(x[2]);
   x[3] = InvMixColumn(x[3]);
}

uint32_t SE_word(uint32_t x) {
   uint32_t I[8] = {0};

   for(size_t i = 0; i != 8; ++i) {
      I[i] = (x >> (7 - i)) & 0x01010101;
   }

   AES_SBOX(I);

   x = 0;

   for(size_t i = 0; i != 8; ++i) {
      x |= ((I[i] & 0x01010101) << (7 - i));
   }

   return x;
}

void aes_key_schedule(const uint8_t key[],
                      size_t length,
                      secure_vector<uint32_t>& EK,
                      secure_vector<uint32_t>& DK,
                      bool bswap_keys = false) {
   static const uint32_t RC[10] = {0x01000000,
                                   0x02000000,
                                   0x04000000,
                                   0x08000000,
                                   0x10000000,
                                   0x20000000,
                                   0x40000000,
                                   0x80000000,
                                   0x1B000000,
                                   0x36000000};

   const size_t X = length / 4;

   // Can't happen, but make static analyzers happy
   BOTAN_ASSERT_NOMSG(X == 4 || X == 6 || X == 8);

   const size_t rounds = (length / 4) + 6;

   // Help the optimizer
   BOTAN_ASSERT_NOMSG(rounds == 10 || rounds == 12 || rounds == 14);

   CT::poison(key, length);

   const size_t KS_len = length + 28;
   EK.resize(KS_len);
   DK.resize(KS_len);

   for(size_t i = 0; i != X; ++i) {
      EK[i] = load_be<uint32_t>(key, i);
   }

   for(size_t i = X; i < 4 * (rounds + 1); i += X) {
      EK[i] = EK[i - X] ^ RC[(i - X) / X] ^ rotl<8>(SE_word(EK[i - 1]));

      for(size_t j = 1; j != X && (i + j) < EK.size(); ++j) {
         EK[i + j] = EK[i + j - X];

         if(X == 8 && j == 4) {
            EK[i + j] ^= SE_word(EK[i + j - 1]);
         } else {
            EK[i + j] ^= EK[i + j - 1];
         }
      }
   }

   for(size_t i = 0; i != 4 * (rounds + 1); i += 4) {
      DK[i] = EK[4 * rounds - i];
      DK[i + 1] = EK[4 * rounds - i + 1];
      DK[i + 2] = EK[4 * rounds - i + 2];
      DK[i + 3] = EK[4 * rounds - i + 3];
   }

   for(size_t i = 4; i != 4 * rounds; i += 4) {
      InvMixColumn_x4(&DK[i]);
   }

   if(bswap_keys) {
      // HW AES on little endian needs the subkeys to be byte reversed
      for(size_t i = 0; i != KS_len; ++i) {
         EK[i] = reverse_bytes(EK[i]);
         DK[i] = reverse_bytes(DK[i]);
      }
   }

   CT::unpoison(EK.data(), EK.size());
   CT::unpoison(DK.data(), DK.size());
   CT::unpoison(key, length);
}

size_t aes_parallelism() {
#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return 8;  // pipelined
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return 4;  // pipelined
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return 2;  // pipelined
   }
#endif

   // bitsliced:
   return 2;
}

std::string aes_provider() {
#if defined(BOTAN_HAS_AES_VAES)
   if(auto feat = CPUID::check(CPUID::Feature::AVX2_AES)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(auto feat = CPUID::check(CPUID::Feature::HW_AES)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(auto feat = CPUID::check(CPUID::Feature::SIMD_4X32)) {
      return *feat;
   }
#endif

   return "base";
}

}  // namespace

std::string AES_128::provider() const {
   return aes_provider();
}

std::string AES_192::provider() const {
   return aes_provider();
}

std::string AES_256::provider() const {
   return aes_provider();
}

size_t AES_128::parallelism() const {
   return aes_parallelism();
}

size_t AES_192::parallelism() const {
   return aes_parallelism();
}

size_t AES_256::parallelism() const {
   return aes_parallelism();
}

bool AES_128::has_keying_material() const {
   return !m_EK.empty();
}

bool AES_192::has_keying_material() const {
   return !m_EK.empty();
}

bool AES_256::has_keying_material() const {
   return !m_EK.empty();
}

void AES_128::encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_encrypt_n(in, out, blocks);
   }
#endif

   aes_encrypt_n(in, out, blocks, m_EK);
}

void AES_128::decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_decrypt_n(in, out, blocks);
   }
#endif

   aes_decrypt_n(in, out, blocks, m_DK);
}

void AES_128::key_schedule(std::span<const uint8_t> key) {
#if defined(BOTAN_HAS_AES_NI)
   if(CPUID::has(CPUID::Feature::AESNI)) {
      return aesni_key_schedule(key.data(), key.size());
   }
#endif

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, true);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      constexpr bool is_little_endian = std::endian::native == std::endian::little;
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, is_little_endian);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_key_schedule(key.data(), key.size());
   }
#endif

   aes_key_schedule(key.data(), key.size(), m_EK, m_DK);
}

void AES_128::clear() {
   zap(m_EK);
   zap(m_DK);
}

void AES_192::encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_encrypt_n(in, out, blocks);
   }
#endif

   aes_encrypt_n(in, out, blocks, m_EK);
}

void AES_192::decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_decrypt_n(in, out, blocks);
   }
#endif

   aes_decrypt_n(in, out, blocks, m_DK);
}

void AES_192::key_schedule(std::span<const uint8_t> key) {
#if defined(BOTAN_HAS_AES_NI)
   if(CPUID::has(CPUID::Feature::AESNI)) {
      return aesni_key_schedule(key.data(), key.size());
   }
#endif

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, true);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      constexpr bool is_little_endian = std::endian::native == std::endian::little;
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, is_little_endian);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_key_schedule(key.data(), key.size());
   }
#endif

   aes_key_schedule(key.data(), key.size(), m_EK, m_DK);
}

void AES_192::clear() {
   zap(m_EK);
   zap(m_DK);
}

void AES_256::encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_encrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_encrypt_n(in, out, blocks);
   }
#endif

   aes_encrypt_n(in, out, blocks, m_EK);
}

void AES_256::decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   assert_key_material_set();

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return x86_vaes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      return hw_aes_decrypt_n(in, out, blocks);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_decrypt_n(in, out, blocks);
   }
#endif

   aes_decrypt_n(in, out, blocks, m_DK);
}

void AES_256::key_schedule(std::span<const uint8_t> key) {
#if defined(BOTAN_HAS_AES_NI)
   if(CPUID::has(CPUID::Feature::AESNI)) {
      return aesni_key_schedule(key.data(), key.size());
   }
#endif

#if defined(BOTAN_HAS_AES_VAES)
   if(CPUID::has(CPUID::Feature::AVX2_AES)) {
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, true);
   }
#endif

#if defined(BOTAN_HAS_HW_AES_SUPPORT)
   if(CPUID::has(CPUID::Feature::HW_AES)) {
      constexpr bool is_little_endian = std::endian::native == std::endian::little;
      return aes_key_schedule(key.data(), key.size(), m_EK, m_DK, is_little_endian);
   }
#endif

#if defined(BOTAN_HAS_AES_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return vperm_key_schedule(key.data(), key.size());
   }
#endif

   aes_key_schedule(key.data(), key.size(), m_EK, m_DK);
}

void AES_256::clear() {
   zap(m_EK);
   zap(m_DK);
}

}  // namespace Botan
/*
* AES using ARMv8
* Contributed by Jeffrey Walton
*
* Further changes
* (C) 2017,2018 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <arm_neon.h>

namespace Botan {

namespace AES_AARCH64 {

namespace {

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void enc(uint8x16_t& B, uint8x16_t K) {
   B = vaesmcq_u8(vaeseq_u8(B, K));
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void enc4(
   uint8x16_t& B0, uint8x16_t& B1, uint8x16_t& B2, uint8x16_t& B3, uint8x16_t K) {
   B0 = vaesmcq_u8(vaeseq_u8(B0, K));
   B1 = vaesmcq_u8(vaeseq_u8(B1, K));
   B2 = vaesmcq_u8(vaeseq_u8(B2, K));
   B3 = vaesmcq_u8(vaeseq_u8(B3, K));
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void enc_last(uint8x16_t& B, uint8x16_t K, uint8x16_t K2) {
   B = veorq_u8(vaeseq_u8(B, K), K2);
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void enc4_last(
   uint8x16_t& B0, uint8x16_t& B1, uint8x16_t& B2, uint8x16_t& B3, uint8x16_t K, uint8x16_t K2) {
   B0 = veorq_u8(vaeseq_u8(B0, K), K2);
   B1 = veorq_u8(vaeseq_u8(B1, K), K2);
   B2 = veorq_u8(vaeseq_u8(B2, K), K2);
   B3 = veorq_u8(vaeseq_u8(B3, K), K2);
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void dec(uint8x16_t& B, uint8x16_t K) {
   B = vaesimcq_u8(vaesdq_u8(B, K));
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void dec4(
   uint8x16_t& B0, uint8x16_t& B1, uint8x16_t& B2, uint8x16_t& B3, uint8x16_t K) {
   B0 = vaesimcq_u8(vaesdq_u8(B0, K));
   B1 = vaesimcq_u8(vaesdq_u8(B1, K));
   B2 = vaesimcq_u8(vaesdq_u8(B2, K));
   B3 = vaesimcq_u8(vaesdq_u8(B3, K));
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void dec_last(uint8x16_t& B, uint8x16_t K, uint8x16_t K2) {
   B = veorq_u8(vaesdq_u8(B, K), K2);
}

BOTAN_FORCE_INLINE BOTAN_FN_ISA_AES void dec4_last(
   uint8x16_t& B0, uint8x16_t& B1, uint8x16_t& B2, uint8x16_t& B3, uint8x16_t K, uint8x16_t K2) {
   B0 = veorq_u8(vaesdq_u8(B0, K), K2);
   B1 = veorq_u8(vaesdq_u8(B1, K), K2);
   B2 = veorq_u8(vaesdq_u8(B2, K), K2);
   B3 = veorq_u8(vaesdq_u8(B3, K), K2);
}

}  // namespace

}  // namespace AES_AARCH64

/*
* AES-128 Encryption
*/
BOTAN_FN_ISA_AES void AES_128::hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_EK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      enc4(B0, B1, B2, B3, K0);
      enc4(B0, B1, B2, B3, K1);
      enc4(B0, B1, B2, B3, K2);
      enc4(B0, B1, B2, B3, K3);
      enc4(B0, B1, B2, B3, K4);
      enc4(B0, B1, B2, B3, K5);
      enc4(B0, B1, B2, B3, K6);
      enc4(B0, B1, B2, B3, K7);
      enc4(B0, B1, B2, B3, K8);
      enc4_last(B0, B1, B2, B3, K9, K10);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      enc(B, K0);
      enc(B, K1);
      enc(B, K2);
      enc(B, K3);
      enc(B, K4);
      enc(B, K5);
      enc(B, K6);
      enc(B, K7);
      enc(B, K8);
      enc_last(B, K9, K10);
      vst1q_u8(out + 16 * i, B);
   }
}

/*
* AES-128 Decryption
*/
BOTAN_FN_ISA_AES void AES_128::hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_DK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      dec4(B0, B1, B2, B3, K0);
      dec4(B0, B1, B2, B3, K1);
      dec4(B0, B1, B2, B3, K2);
      dec4(B0, B1, B2, B3, K3);
      dec4(B0, B1, B2, B3, K4);
      dec4(B0, B1, B2, B3, K5);
      dec4(B0, B1, B2, B3, K6);
      dec4(B0, B1, B2, B3, K7);
      dec4(B0, B1, B2, B3, K8);
      dec4_last(B0, B1, B2, B3, K9, K10);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      dec(B, K0);
      dec(B, K1);
      dec(B, K2);
      dec(B, K3);
      dec(B, K4);
      dec(B, K5);
      dec(B, K6);
      dec(B, K7);
      dec(B, K8);
      dec_last(B, K9, K10);
      vst1q_u8(out + 16 * i, B);
   }
}

/*
* AES-192 Encryption
*/
BOTAN_FN_ISA_AES void AES_192::hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_EK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);
   const uint8x16_t K11 = vld1q_u8(skey + 11 * 16);
   const uint8x16_t K12 = vld1q_u8(skey + 12 * 16);

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      enc4(B0, B1, B2, B3, K0);
      enc4(B0, B1, B2, B3, K1);
      enc4(B0, B1, B2, B3, K2);
      enc4(B0, B1, B2, B3, K3);
      enc4(B0, B1, B2, B3, K4);
      enc4(B0, B1, B2, B3, K5);
      enc4(B0, B1, B2, B3, K6);
      enc4(B0, B1, B2, B3, K7);
      enc4(B0, B1, B2, B3, K8);
      enc4(B0, B1, B2, B3, K9);
      enc4(B0, B1, B2, B3, K10);
      enc4_last(B0, B1, B2, B3, K11, K12);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      enc(B, K0);
      enc(B, K1);
      enc(B, K2);
      enc(B, K3);
      enc(B, K4);
      enc(B, K5);
      enc(B, K6);
      enc(B, K7);
      enc(B, K8);
      enc(B, K9);
      enc(B, K10);
      enc_last(B, K11, K12);
      vst1q_u8(out + 16 * i, B);
   }
}

/*
* AES-192 Decryption
*/
BOTAN_FN_ISA_AES void AES_192::hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_DK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);
   const uint8x16_t K11 = vld1q_u8(skey + 11 * 16);
   const uint8x16_t K12 = vld1q_u8(skey + 12 * 16);

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      dec4(B0, B1, B2, B3, K0);
      dec4(B0, B1, B2, B3, K1);
      dec4(B0, B1, B2, B3, K2);
      dec4(B0, B1, B2, B3, K3);
      dec4(B0, B1, B2, B3, K4);
      dec4(B0, B1, B2, B3, K5);
      dec4(B0, B1, B2, B3, K6);
      dec4(B0, B1, B2, B3, K7);
      dec4(B0, B1, B2, B3, K8);
      dec4(B0, B1, B2, B3, K9);
      dec4(B0, B1, B2, B3, K10);
      dec4_last(B0, B1, B2, B3, K11, K12);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      dec(B, K0);
      dec(B, K1);
      dec(B, K2);
      dec(B, K3);
      dec(B, K4);
      dec(B, K5);
      dec(B, K6);
      dec(B, K7);
      dec(B, K8);
      dec(B, K9);
      dec(B, K10);
      dec_last(B, K11, K12);
      vst1q_u8(out + 16 * i, B);
   }
}

/*
* AES-256 Encryption
*/
BOTAN_FN_ISA_AES void AES_256::hw_aes_encrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_EK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);
   const uint8x16_t K11 = vld1q_u8(skey + 11 * 16);
   const uint8x16_t K12 = vld1q_u8(skey + 12 * 16);
   const uint8x16_t K13 = vld1q_u8(skey + 13 * 16);
   const uint8x16_t K14 = vld1q_u8(skey + 14 * 16);

   using namespace AES_AARCH64;

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      enc4(B0, B1, B2, B3, K0);
      enc4(B0, B1, B2, B3, K1);
      enc4(B0, B1, B2, B3, K2);
      enc4(B0, B1, B2, B3, K3);
      enc4(B0, B1, B2, B3, K4);
      enc4(B0, B1, B2, B3, K5);
      enc4(B0, B1, B2, B3, K6);
      enc4(B0, B1, B2, B3, K7);
      enc4(B0, B1, B2, B3, K8);
      enc4(B0, B1, B2, B3, K9);
      enc4(B0, B1, B2, B3, K10);
      enc4(B0, B1, B2, B3, K11);
      enc4(B0, B1, B2, B3, K12);
      enc4_last(B0, B1, B2, B3, K13, K14);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      enc(B, K0);
      enc(B, K1);
      enc(B, K2);
      enc(B, K3);
      enc(B, K4);
      enc(B, K5);
      enc(B, K6);
      enc(B, K7);
      enc(B, K8);
      enc(B, K9);
      enc(B, K10);
      enc(B, K11);
      enc(B, K12);
      enc_last(B, K13, K14);
      vst1q_u8(out + 16 * i, B);
   }
}

/*
* AES-256 Decryption
*/
BOTAN_FN_ISA_AES void AES_256::hw_aes_decrypt_n(const uint8_t in[], uint8_t out[], size_t blocks) const {
   const uint8_t* skey = reinterpret_cast<const uint8_t*>(m_DK.data());

   const uint8x16_t K0 = vld1q_u8(skey + 0 * 16);
   const uint8x16_t K1 = vld1q_u8(skey + 1 * 16);
   const uint8x16_t K2 = vld1q_u8(skey + 2 * 16);
   const uint8x16_t K3 = vld1q_u8(skey + 3 * 16);
   const uint8x16_t K4 = vld1q_u8(skey + 4 * 16);
   const uint8x16_t K5 = vld1q_u8(skey + 5 * 16);
   const uint8x16_t K6 = vld1q_u8(skey + 6 * 16);
   const uint8x16_t K7 = vld1q_u8(skey + 7 * 16);
   const uint8x16_t K8 = vld1q_u8(skey + 8 * 16);
   const uint8x16_t K9 = vld1q_u8(skey + 9 * 16);
   const uint8x16_t K10 = vld1q_u8(skey + 10 * 16);
   const uint8x16_t K11 = vld1q_u8(skey + 11 * 16);
   const uint8x16_t K12 = vld1q_u8(skey + 12 * 16);
   const uint8x16_t K13 = vld1q_u8(skey + 13 * 16);
   const uint8x16_t K14 = vld1q_u8(skey + 14 * 16);

   using namespace AES_AARCH64;

   while(blocks >= 4) {
      uint8x16_t B0 = vld1q_u8(in);
      uint8x16_t B1 = vld1q_u8(in + 16);
      uint8x16_t B2 = vld1q_u8(in + 32);
      uint8x16_t B3 = vld1q_u8(in + 48);

      dec4(B0, B1, B2, B3, K0);
      dec4(B0, B1, B2, B3, K1);
      dec4(B0, B1, B2, B3, K2);
      dec4(B0, B1, B2, B3, K3);
      dec4(B0, B1, B2, B3, K4);
      dec4(B0, B1, B2, B3, K5);
      dec4(B0, B1, B2, B3, K6);
      dec4(B0, B1, B2, B3, K7);
      dec4(B0, B1, B2, B3, K8);
      dec4(B0, B1, B2, B3, K9);
      dec4(B0, B1, B2, B3, K10);
      dec4(B0, B1, B2, B3, K11);
      dec4(B0, B1, B2, B3, K12);
      dec4_last(B0, B1, B2, B3, K13, K14);

      vst1q_u8(out, B0);
      vst1q_u8(out + 16, B1);
      vst1q_u8(out + 32, B2);
      vst1q_u8(out + 48, B3);

      in += 16 * 4;
      out += 16 * 4;
      blocks -= 4;
   }

   for(size_t i = 0; i != blocks; ++i) {
      uint8x16_t B = vld1q_u8(in + 16 * i);
      dec(B, K0);
      dec(B, K1);
      dec(B, K2);
      dec(B, K3);
      dec(B, K4);
      dec(B, K5);
      dec(B, K6);
      dec(B, K7);
      dec(B, K8);
      dec(B, K9);
      dec(B, K10);
      dec(B, K11);
      dec(B, K12);
      dec_last(B, K13, K14);
      vst1q_u8(out + 16 * i, B);
   }
}

}  // namespace Botan
/**
* (C) 2018,2019,2022 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <limits>

#if defined(BOTAN_HAS_THREAD_UTILS)
#endif

#if defined(BOTAN_HAS_CPUID)
#endif

namespace Botan {

namespace {

const size_t SYNC_POINTS = 4;

void argon2_H0(uint8_t H0[64],
               HashFunction& blake2b,
               size_t output_len,
               const char* password,
               size_t password_len,
               const uint8_t salt[],
               size_t salt_len,
               const uint8_t key[],
               size_t key_len,
               const uint8_t ad[],
               size_t ad_len,
               size_t y,
               size_t p,
               size_t M,
               size_t t) {
   const uint8_t v = 19;  // Argon2 version code

   blake2b.update_le(static_cast<uint32_t>(p));
   blake2b.update_le(static_cast<uint32_t>(output_len));
   blake2b.update_le(static_cast<uint32_t>(M));
   blake2b.update_le(static_cast<uint32_t>(t));
   blake2b.update_le(static_cast<uint32_t>(v));
   blake2b.update_le(static_cast<uint32_t>(y));

   blake2b.update_le(static_cast<uint32_t>(password_len));
   blake2b.update(as_span_of_bytes(password, password_len));

   blake2b.update_le(static_cast<uint32_t>(salt_len));
   blake2b.update(salt, salt_len);

   blake2b.update_le(static_cast<uint32_t>(key_len));
   blake2b.update(key, key_len);

   blake2b.update_le(static_cast<uint32_t>(ad_len));
   blake2b.update(ad, ad_len);

   blake2b.final(H0);
}

void extract_key(uint8_t output[], size_t output_len, const secure_vector<uint64_t>& B, size_t memory, size_t threads) {
   const size_t lanes = memory / threads;

   uint64_t sum[128] = {0};

   for(size_t lane = 0; lane != threads; ++lane) {
      const size_t start = 128 * (lane * lanes + lanes - 1);
      const size_t end = 128 * (lane * lanes + lanes);

      for(size_t j = start; j != end; ++j) {
         sum[j % 128] ^= B[j];
      }
   }

   if(output_len <= 64) {
      auto blake2b = HashFunction::create_or_throw(fmt("BLAKE2b({})", output_len * 8));
      blake2b->update_le(static_cast<uint32_t>(output_len));
      for(size_t i = 0; i != 128; ++i) {  // NOLINT(modernize-loop-convert)
         blake2b->update_le(sum[i]);
      }
      blake2b->final(output);
   } else {
      secure_vector<uint8_t> T(64);

      auto blake2b = HashFunction::create_or_throw("BLAKE2b(512)");
      blake2b->update_le(static_cast<uint32_t>(output_len));
      for(size_t i = 0; i != 128; ++i) {  // NOLINT(modernize-loop-convert)
         blake2b->update_le(sum[i]);
      }
      blake2b->final(std::span{T});

      while(output_len > 64) {
         copy_mem(output, T.data(), 32);
         output_len -= 32;
         output += 32;

         if(output_len > 64) {
            blake2b->update(T);
            blake2b->final(std::span{T});
         }
      }

      if(output_len == 64) {
         blake2b->update(T);
         blake2b->final(output);
      } else {
         auto blake2b_f = HashFunction::create_or_throw(fmt("BLAKE2b({})", output_len * 8));
         blake2b_f->update(T);
         blake2b_f->final(output);
      }
   }
}

void init_blocks(
   secure_vector<uint64_t>& B, HashFunction& blake2b, const uint8_t H0[64], size_t memory, size_t threads) {
   BOTAN_ASSERT_NOMSG(B.size() >= threads * 256);

   for(size_t i = 0; i != threads; ++i) {
      const size_t B_off = i * (memory / threads);

      BOTAN_ASSERT_NOMSG(B.size() >= 128 * (B_off + 2));

      for(size_t j = 0; j != 2; ++j) {
         uint8_t T[64] = {0};

         blake2b.update_le(static_cast<uint32_t>(1024));
         blake2b.update(H0, 64);
         blake2b.update_le(static_cast<uint32_t>(j));
         blake2b.update_le(static_cast<uint32_t>(i));
         blake2b.final(T);

         for(size_t k = 0; k != 30; ++k) {
            load_le(&B[128 * (B_off + j) + 4 * k], T, 32 / 8);
            blake2b.update(T, 64);
            blake2b.final(T);
         }

         load_le(&B[128 * (B_off + j) + 4 * 30], T, 64 / 8);
      }
   }
}

BOTAN_FORCE_INLINE void blamka_G(uint64_t& A, uint64_t& B, uint64_t& C, uint64_t& D) {
   A += B + (static_cast<uint64_t>(2) * static_cast<uint32_t>(A)) * static_cast<uint32_t>(B);
   D = rotr<32>(A ^ D);

   C += D + (static_cast<uint64_t>(2) * static_cast<uint32_t>(C)) * static_cast<uint32_t>(D);
   B = rotr<24>(B ^ C);

   A += B + (static_cast<uint64_t>(2) * static_cast<uint32_t>(A)) * static_cast<uint32_t>(B);
   D = rotr<16>(A ^ D);

   C += D + (static_cast<uint64_t>(2) * static_cast<uint32_t>(C)) * static_cast<uint32_t>(D);
   B = rotr<63>(B ^ C);
}

}  // namespace

void Argon2::blamka(uint64_t N[128], uint64_t T[128]) {
#if defined(BOTAN_HAS_ARGON2_AVX512)
   if(CPUID::has(CPUID::Feature::AVX512)) {
      return Argon2::blamka_avx512(N, T);
   }
#endif

#if defined(BOTAN_HAS_ARGON2_AVX2)
   if(CPUID::has(CPUID::Feature::AVX2)) {
      return Argon2::blamka_avx2(N, T);
   }
#endif

#if defined(BOTAN_HAS_ARGON2_SIMD64)
   if(CPUID::has(CPUID::Feature::SIMD_2X64)) {
      return Argon2::blamka_simd64(N, T);
   }
#endif

   copy_mem(T, N, 128);

   for(size_t i = 0; i != 128; i += 16) {
      blamka_G(T[i + 0], T[i + 4], T[i + 8], T[i + 12]);
      blamka_G(T[i + 1], T[i + 5], T[i + 9], T[i + 13]);
      blamka_G(T[i + 2], T[i + 6], T[i + 10], T[i + 14]);
      blamka_G(T[i + 3], T[i + 7], T[i + 11], T[i + 15]);

      blamka_G(T[i + 0], T[i + 5], T[i + 10], T[i + 15]);
      blamka_G(T[i + 1], T[i + 6], T[i + 11], T[i + 12]);
      blamka_G(T[i + 2], T[i + 7], T[i + 8], T[i + 13]);
      blamka_G(T[i + 3], T[i + 4], T[i + 9], T[i + 14]);
   }

   for(size_t i = 0; i != 128 / 8; i += 2) {
      blamka_G(T[i + 0], T[i + 32], T[i + 64], T[i + 96]);
      blamka_G(T[i + 1], T[i + 33], T[i + 65], T[i + 97]);
      blamka_G(T[i + 16], T[i + 48], T[i + 80], T[i + 112]);
      blamka_G(T[i + 17], T[i + 49], T[i + 81], T[i + 113]);

      blamka_G(T[i + 0], T[i + 33], T[i + 80], T[i + 113]);
      blamka_G(T[i + 1], T[i + 48], T[i + 81], T[i + 96]);
      blamka_G(T[i + 16], T[i + 49], T[i + 64], T[i + 97]);
      blamka_G(T[i + 17], T[i + 32], T[i + 65], T[i + 112]);
   }

   for(size_t i = 0; i != 128; ++i) {
      N[i] ^= T[i];
   }
}

namespace {

void gen_2i_addresses(uint64_t T[128],
                      uint64_t B[128],
                      size_t n,
                      size_t lane,
                      size_t slice,
                      size_t memory,
                      size_t time,
                      size_t mode,
                      size_t cnt) {
   clear_mem(B, 128);

   B[0] = n;
   B[1] = lane;
   B[2] = slice;
   B[3] = memory;
   B[4] = time;
   B[5] = mode;
   B[6] = cnt;

   for(size_t r = 0; r != 2; ++r) {
      Argon2::blamka(B, T);
   }
}

// Reduce random modulo Argon2 thread count (normally a power of 2)
inline size_t mod_threads(uint32_t random, size_t threads) {
   if(is_power_of_2(threads)) {
      return random & static_cast<uint32_t>(threads - 1);
   } else {
      return random % threads;
   }
}

// Reduce alpha modulo the lane length; always a multiple of 4 and commonly a power of 2
inline size_t mod_lanes(uint64_t alpha, size_t lanes) {
   if(is_power_of_2(lanes)) {
      return static_cast<size_t>(alpha & static_cast<uint64_t>(lanes - 1));
   } else {
      return alpha % lanes;
   }
}

uint32_t index_alpha(
   uint64_t random, size_t lanes, size_t segments, size_t threads, size_t n, size_t slice, size_t lane, size_t index) {
   size_t ref_lane = mod_threads(static_cast<uint32_t>(random >> 32), threads);

   if(n == 0 && slice == 0) {
      ref_lane = lane;
   }

   size_t m = 3 * segments;
   size_t s = ((slice + 1) % 4) * segments;

   if(lane == ref_lane) {
      m += index;
   }

   if(n == 0) {
      m = slice * segments;
      s = 0;
      if(slice == 0 || lane == ref_lane) {
         m += index;
      }
   }

   if(index == 0 || lane == ref_lane) {
      m -= 1;
   }

   uint64_t p = static_cast<uint32_t>(random);
   p = (p * p) >> 32;
   p = (p * m) >> 32;

   return static_cast<uint32_t>(ref_lane * lanes + mod_lanes(s + m - (p + 1), lanes));
}

void process_block(secure_vector<uint64_t>& B,
                   size_t n,
                   size_t slice,
                   size_t lane,
                   size_t lanes,
                   size_t segments,
                   size_t threads,
                   uint8_t mode,
                   size_t memory,
                   size_t time) {
   uint64_t T[128];
   size_t index = 0;
   if(n == 0 && slice == 0) {
      index = 2;
   }

   const bool use_2i = mode == 1 || (mode == 2 && n == 0 && slice < SYNC_POINTS / 2);

   uint64_t addresses[128];
   size_t address_counter = 1;

   if(use_2i) {
      gen_2i_addresses(T, addresses, n, lane, slice, memory, time, mode, address_counter);
   }

   while(index < segments) {
      const size_t offset = lane * lanes + slice * segments + index;

      size_t prev = offset - 1;
      if(index == 0 && slice == 0) {
         prev += lanes;
      }

      if(use_2i && index > 0 && index % 128 == 0) {
         address_counter += 1;
         gen_2i_addresses(T, addresses, n, lane, slice, memory, time, mode, address_counter);
      }

      const uint64_t random = use_2i ? addresses[index % 128] : B.at(128 * prev);
      const size_t new_offset = index_alpha(random, lanes, segments, threads, n, slice, lane, index);

      uint64_t N[128];
      for(size_t i = 0; i != 128; ++i) {
         N[i] = B[128 * prev + i] ^ B[128 * new_offset + i];
      }

      Argon2::blamka(N, T);

      for(size_t i = 0; i != 128; ++i) {
         B[128 * offset + i] ^= N[i];
      }

      index += 1;
   }
}

void process_blocks(secure_vector<uint64_t>& B, size_t t, size_t memory, size_t threads, uint8_t mode) {
   const size_t lanes = memory / threads;
   const size_t segments = lanes / SYNC_POINTS;

#if defined(BOTAN_HAS_THREAD_UTILS)
   if(threads > 1) {
      auto& thread_pool = Thread_Pool::global_instance();

      for(size_t n = 0; n != t; ++n) {
         for(size_t slice = 0; slice != SYNC_POINTS; ++slice) {
            std::vector<std::future<void>> fut_results;
            fut_results.reserve(threads);

            for(size_t lane = 0; lane != threads; ++lane) {
               fut_results.push_back(thread_pool.run(
                  process_block, std::ref(B), n, slice, lane, lanes, segments, threads, mode, memory, t));
            }

            for(auto& fut : fut_results) {
               fut.get();
            }
         }
      }

      return;
   }
#endif

   for(size_t n = 0; n != t; ++n) {
      for(size_t slice = 0; slice != SYNC_POINTS; ++slice) {
         for(size_t lane = 0; lane != threads; ++lane) {
            process_block(B, n, slice, lane, lanes, segments, threads, mode, memory, t);
         }
      }
   }
}

}  // namespace

void Argon2::argon2(uint8_t output[],
                    size_t output_len,
                    const char* password,
                    size_t password_len,
                    const uint8_t salt[],
                    size_t salt_len,
                    const uint8_t key[],
                    size_t key_len,
                    const uint8_t ad[],
                    size_t ad_len) const {
   BOTAN_ARG_CHECK(output_len >= 4 && output_len <= std::numeric_limits<uint32_t>::max(),
                   "Invalid Argon2 output length");
   BOTAN_ARG_CHECK(password_len <= std::numeric_limits<uint32_t>::max(), "Invalid Argon2 password length");
   BOTAN_ARG_CHECK(salt_len <= std::numeric_limits<uint32_t>::max(), "Invalid Argon2 salt length");
   BOTAN_ARG_CHECK(key_len <= std::numeric_limits<uint32_t>::max(), "Invalid Argon2 key length");
   BOTAN_ARG_CHECK(ad_len <= std::numeric_limits<uint32_t>::max(), "Invalid Argon2 ad length");

   auto blake2 = HashFunction::create_or_throw("BLAKE2b");

   uint8_t H0[64] = {0};
   argon2_H0(H0,
             *blake2,
             output_len,
             password,
             password_len,
             salt,
             salt_len,
             key,
             key_len,
             ad,
             ad_len,
             m_family,
             m_p,
             m_M,
             m_t);

   const size_t memory = (m_M / (SYNC_POINTS * m_p)) * (SYNC_POINTS * m_p);

   constexpr size_t M_scale = 1024 / 8;
   secure_vector<uint64_t> B(memory * M_scale);

   init_blocks(B, *blake2, H0, memory, m_p);
   process_blocks(B, m_t, memory, m_p, m_family);

   clear_mem(output, output_len);
   extract_key(output, output_len, B, memory, m_p);
}

}  // namespace Botan
/**
* (C) 2019 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <algorithm>

namespace Botan {

namespace {

std::string argon2_family_name(uint8_t f) {
   switch(f) {
      case 0:
         return "Argon2d";
      case 1:
         return "Argon2i";
      case 2:
         return "Argon2id";
      default:
         throw Invalid_Argument("Unknown Argon2 parameter");
   }
}

constexpr size_t MAX_ARGON_MEMORY_GB = sizeof(size_t) == 4 ? 2 : 8;

}  // namespace

Argon2::Argon2(uint8_t family, size_t M, size_t t, size_t p) : m_family(family), m_M(M), m_t(t), m_p(p) {
   BOTAN_ARG_CHECK(m_family == 0 || m_family == 1 || m_family == 2, "Invalid Argon2 family parameter");
   BOTAN_ARG_CHECK(m_p >= 1 && m_p <= 128, "Invalid Argon2 threads parameter");
   BOTAN_ARG_CHECK(m_M >= 8 * m_p && m_M <= MAX_ARGON_MEMORY_GB * 1024 * 1024, "Invalid Argon2 M parameter");
   BOTAN_ARG_CHECK(m_t >= 1 && m_t <= std::numeric_limits<uint32_t>::max(), "Invalid Argon2 t parameter");
}

void Argon2::derive_key(uint8_t output[],
                        size_t output_len,
                        const char* password,
                        size_t password_len,
                        const uint8_t salt[],
                        size_t salt_len) const {
   argon2(output, output_len, password, password_len, salt, salt_len, nullptr, 0, nullptr, 0);
}

void Argon2::derive_key(uint8_t output[],
                        size_t output_len,
                        const char* password,
                        size_t password_len,
                        const uint8_t salt[],
                        size_t salt_len,
                        const uint8_t ad[],
                        size_t ad_len,
                        const uint8_t key[],
                        size_t key_len) const {
   argon2(output, output_len, password, password_len, salt, salt_len, key, key_len, ad, ad_len);
}

std::string Argon2::to_string() const {
   return fmt("{}({},{},{})", argon2_family_name(m_family), m_M, m_t, m_p);
}

Argon2_Family::Argon2_Family(uint8_t family) : m_family(family) {
   if(m_family != 0 && m_family != 1 && m_family != 2) {
      throw Invalid_Argument("Unknown Argon2 family identifier");
   }
}

std::string Argon2_Family::name() const {
   return argon2_family_name(m_family);
}

std::unique_ptr<PasswordHash> Argon2_Family::tune_params(size_t /*output_length*/,
                                                         uint64_t desired_msec,
                                                         std::optional<size_t> max_memory,
                                                         uint64_t tune_msec) const {
   // If not set use 256 MB as default max
   const size_t max_kib = std::min(MAX_ARGON_MEMORY_GB * 1024 * 1024, max_memory.value_or(256) * 1024);

   // Tune with a large memory otherwise we measure cache vs RAM speeds and underestimate
   // costs for larger params. Default is 36 MiB, or use 128 for long times.
   const size_t tune_M = (desired_msec >= 200 ? 128 : 36) * 1024;
   const size_t p = 1;
   size_t t = 1;

   size_t M = 4 * 1024;

   auto pwhash = this->from_params(tune_M, t, p);

   auto tune_fn = [&]() {
      uint8_t output[64] = {0};
      pwhash->derive_key(output, sizeof(output), "test", 4, nullptr, 0);
   };

   const uint64_t measured_time = measure_cost(tune_msec, tune_fn) / (tune_M / M);

   const uint64_t target_nsec = desired_msec * static_cast<uint64_t>(1000000);

   /*
   * Argon2 scaling rules:
   * k*M, k*t, k*p all increase cost by about k
   *
   * First preference is to increase M up to max allowed value.
   * Any remaining time budget is spent on increasing t.
   */

   uint64_t est_nsec = measured_time;

   if(est_nsec < target_nsec && M < max_kib) {
      const uint64_t desired_cost_increase = (target_nsec + est_nsec - 1) / est_nsec;
      const uint64_t mem_headroom = max_kib / M;

      const uint64_t M_mult = std::min(desired_cost_increase, mem_headroom);
      M *= static_cast<size_t>(M_mult);
      est_nsec *= M_mult;
   }

   if(est_nsec < target_nsec / 2) {
      const uint64_t desired_cost_increase = (target_nsec + est_nsec - 1) / est_nsec;
      t *= static_cast<size_t>(desired_cost_increase);
   }

   return this->from_params(M, t, p);
}

std::unique_ptr<PasswordHash> Argon2_Family::default_params() const {
   return this->from_params(128 * 1024, 1, 1);
}

std::unique_ptr<PasswordHash> Argon2_Family::from_iterations(size_t iter) const {
   /*
   These choices are arbitrary, but should not change in future
   releases since they will break applications expecting deterministic
   mapping from iteration count to params
   */
   const size_t M = iter;
   const size_t t = 1;
   const size_t p = 1;
   return this->from_params(M, t, p);
}

std::unique_ptr<PasswordHash> Argon2_Family::from_params(size_t M, size_t t, size_t p) const {
   return std::make_unique<Argon2>(m_family, M, t, p);
}

}  // namespace Botan
/**
* (C) 2019 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

std::string strip_padding(std::string s) {
   while(!s.empty() && s[s.size() - 1] == '=') {
      s.resize(s.size() - 1);
   }
   return s;
}

std::string argon2_family(uint8_t y) {
   if(y == 0) {
      return "Argon2d";
   } else if(y == 1) {
      return "Argon2i";
   } else if(y == 2) {
      return "Argon2id";
   } else {
      throw Not_Implemented("Unknown Argon2 family type");
   }
}

}  // namespace

std::string argon2_generate_pwhash(const char* password,
                                   size_t password_len,
                                   RandomNumberGenerator& rng,
                                   size_t p,
                                   size_t M,
                                   size_t t,
                                   uint8_t y,
                                   size_t salt_len,
                                   size_t output_len) {
   std::vector<uint8_t> salt(salt_len);
   rng.randomize(salt.data(), salt.size());

   std::vector<uint8_t> output(output_len);

   auto pwdhash_fam = PasswordHashFamily::create_or_throw(argon2_family(y));
   auto pwdhash = pwdhash_fam->from_params(M, t, p);

   pwdhash->derive_key(output.data(), output.size(), password, password_len, salt.data(), salt.size());

   const auto enc_salt = strip_padding(base64_encode(salt));
   const auto enc_output = strip_padding(base64_encode(output));

   const std::string argon2_mode = [&]() -> std::string {
      if(y == 0) {
         return "d";
      } else if(y == 1) {
         return "i";
      } else {
         return "id";
      }
   }();

   return fmt("$argon2{}$v=19$m={},t={},p={}${}${}", argon2_mode, M, t, p, enc_salt, enc_output);
}

bool argon2_check_pwhash(const char* password, size_t password_len, std::string_view input_hash) {
   try {
      const std::vector<std::string> parts = split_on(input_hash, '$');

      if(parts.size() != 5) {
         return false;
      }

      uint8_t family = 0;

      if(parts[0] == "argon2d") {
         family = 0;
      } else if(parts[0] == "argon2i") {
         family = 1;
      } else if(parts[0] == "argon2id") {
         family = 2;
      } else {
         return false;
      }

      if(parts[1] != "v=19") {
         return false;
      }

      const std::vector<std::string> params = split_on(parts[2], ',');

      if(params.size() != 3) {
         return false;
      }

      size_t M = 0;
      size_t t = 0;
      size_t p = 0;

      for(const auto& param_str : params) {
         const std::vector<std::string> param = split_on(param_str, '=');

         if(param.size() != 2) {
            return false;
         }

         const std::string_view key = param[0];
         const size_t val = to_u32bit(param[1]);
         if(key == "m") {
            M = val;
         } else if(key == "t") {
            t = val;
         } else if(key == "p") {
            p = val;
         } else {
            return false;
         }
      }

      std::vector<uint8_t> salt(base64_decode_max_output(parts[3].size()));
      salt.resize(base64_decode(salt.data(), parts[3], false));

      std::vector<uint8_t> hash(base64_decode_max_output(parts[4].size()));
      hash.resize(base64_decode(hash.data(), parts[4], false));

      if(hash.size() < 4) {
         return false;
      }

      std::vector<uint8_t> generated(hash.size());
      auto pwdhash_fam = PasswordHashFamily::create_or_throw(argon2_family(family));
      auto pwdhash = pwdhash_fam->from_params(M, t, p);

      pwdhash->derive_key(generated.data(), generated.size(), password, password_len, salt.data(), salt.size());

      return CT::is_equal(generated.data(), hash.data(), generated.size()).as_bool();
   } catch(...) {
      return false;
   }
}

}  // namespace Botan
/*
* (C) 2016 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_ENTROPY_SOURCE)
#endif

#if defined(BOTAN_HAS_SYSTEM_RNG)
#endif

namespace Botan {

namespace {

std::unique_ptr<MessageAuthenticationCode> auto_rng_hmac() {
   const std::string possible_auto_rng_hmacs[] = {
      "HMAC(SHA-512)",
      "HMAC(SHA-256)",
   };

   for(const auto& hmac : possible_auto_rng_hmacs) {
      if(auto mac = MessageAuthenticationCode::create(hmac)) {
         return mac;
      }
   }

   // This shouldn't happen since this module has a dependency on sha2_32
   throw Internal_Error("AutoSeeded_RNG: No usable HMAC hash found");
}

}  // namespace

AutoSeeded_RNG::AutoSeeded_RNG(AutoSeeded_RNG&& other) noexcept = default;

AutoSeeded_RNG::~AutoSeeded_RNG() = default;

AutoSeeded_RNG::AutoSeeded_RNG(RandomNumberGenerator& underlying_rng, size_t reseed_interval) {
   m_rng = std::make_unique<HMAC_DRBG>(auto_rng_hmac(), underlying_rng, reseed_interval);

   force_reseed();
}

AutoSeeded_RNG::AutoSeeded_RNG(Entropy_Sources& entropy_sources, size_t reseed_interval) {
   m_rng = std::make_unique<HMAC_DRBG>(auto_rng_hmac(), entropy_sources, reseed_interval);

   force_reseed();
}

AutoSeeded_RNG::AutoSeeded_RNG(RandomNumberGenerator& underlying_rng,
                               Entropy_Sources& entropy_sources,
                               size_t reseed_interval) {
   m_rng = std::make_unique<HMAC_DRBG>(auto_rng_hmac(), underlying_rng, entropy_sources, reseed_interval);

   force_reseed();
}

AutoSeeded_RNG::AutoSeeded_RNG(size_t reseed_interval) {
#if defined(BOTAN_HAS_SYSTEM_RNG)
   m_rng = std::make_unique<HMAC_DRBG>(auto_rng_hmac(), system_rng(), reseed_interval);
#elif defined(BOTAN_HAS_ENTROPY_SOURCE)
   m_rng = std::make_unique<HMAC_DRBG>(auto_rng_hmac(), Entropy_Sources::global_sources(), reseed_interval);
#else
   BOTAN_UNUSED(reseed_interval);
   throw Not_Implemented("AutoSeeded_RNG default constructor not available due to no RNG or entropy sources");
#endif

   force_reseed();
}

void AutoSeeded_RNG::force_reseed() {
   m_rng->force_reseed();
   m_rng->next_byte();

   if(!m_rng->is_seeded()) {
      throw Internal_Error("AutoSeeded_RNG reseeding failed");
   }
}

bool AutoSeeded_RNG::is_seeded() const {
   return m_rng->is_seeded();
}

void AutoSeeded_RNG::clear() {
   m_rng->clear();
}

std::string AutoSeeded_RNG::name() const {
   return m_rng->name();
}

size_t AutoSeeded_RNG::reseed_from_sources(Entropy_Sources& srcs, size_t poll_bits) {
   return m_rng->reseed_from_sources(srcs, poll_bits);
}

void AutoSeeded_RNG::fill_bytes_with_input(std::span<uint8_t> out, std::span<const uint8_t> in) {
   if(out.empty() && in.empty()) {
      return;
   } else if(in.empty()) {
      m_rng->randomize_with_ts_input(out);
   } else {
      m_rng->randomize_with_input(out, in);
   }
}

}  // namespace Botan
/*
* (C) 2019 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

void Buffered_Computation::update(std::string_view str) {
   add_data(as_span_of_bytes(str));
}

void Buffered_Computation::update_be(uint16_t val) {
   uint8_t inb[sizeof(val)];
   store_be(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::update_be(uint32_t val) {
   uint8_t inb[sizeof(val)];
   store_be(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::update_be(uint64_t val) {
   uint8_t inb[sizeof(val)];
   store_be(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::update_le(uint16_t val) {
   uint8_t inb[sizeof(val)];
   store_le(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::update_le(uint32_t val) {
   uint8_t inb[sizeof(val)];
   store_le(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::update_le(uint64_t val) {
   uint8_t inb[sizeof(val)];
   store_le(val, inb);
   add_data({inb, sizeof(inb)});
}

void Buffered_Computation::final(std::span<uint8_t> out) {
   BOTAN_ARG_CHECK(out.size() >= output_length(), "Output buffer has insufficient capacity");
   // Pass exactly output_length() bytes so that an oversized buffer has the
   // result written to its leading bytes with the remainder left untouched.
   final_result(out.first(output_length()));
}

}  // namespace Botan
/*
* (C) 2018 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

void SymmetricAlgorithm::set_key(const OctetString& key) {
   set_key(std::span{key.begin(), key.length()});
}

void SymmetricAlgorithm::throw_key_not_set_error() const {
   throw Key_Not_Set(name());
}

void SymmetricAlgorithm::set_key(std::span<const uint8_t> key) {
   if(!valid_keylength(key.size())) {
      throw Invalid_Key_Length(name(), key.size());
   }
   key_schedule(key);
}

}  // namespace Botan
/*
* OctetString
* (C) 1999-2007 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

/*
* Create an OctetString from RNG output
*/
OctetString::OctetString(RandomNumberGenerator& rng, size_t len) {
   rng.random_vec(m_data, len);
}

/*
* Create an OctetString from a hex string
*/
OctetString::OctetString(std::string_view hex_string) {
   if(!hex_string.empty()) {
      m_data.resize(1 + hex_string.length() / 2);
      m_data.resize(hex_decode(m_data.data(), hex_string));
   }
}

/*
* Create an OctetString from a byte string
*/
OctetString::OctetString(const uint8_t in[], size_t n) {
   m_data.assign(in, in + n);
}

namespace {

uint8_t odd_parity_of(uint8_t x) {
   uint8_t f = x | 0x01;
   f ^= (f >> 4);
   f ^= (f >> 2);
   f ^= (f >> 1);

   return (x & 0xFE) ^ (f & 0x01);
}

}  // namespace

/*
* Set the parity of each key byte to odd
*/
void OctetString::set_odd_parity() {
   for(auto& b : m_data) {
      b = odd_parity_of(b);
   }
}

/*
* Hex encode an OctetString
*/
std::string OctetString::to_string() const {
   return hex_encode(m_data.data(), m_data.size());
}

/*
* XOR Operation for OctetStrings
*/
OctetString& OctetString::operator^=(const OctetString& k) {
   if(&k == this) {
      zeroise(m_data);
      return (*this);
   }
   xor_buf(m_data.data(), k.begin(), std::min(length(), k.length()));
   return (*this);
}

/*
* Equality Operation for OctetStrings
*/
bool operator==(const OctetString& s1, const OctetString& s2) {
   return (s1.bits_of() == s2.bits_of());
}

/*
* Inequality Operation for OctetStrings
*/
bool operator!=(const OctetString& s1, const OctetString& s2) {
   return !(s1 == s2);
}

/*
* Append Operation for OctetStrings
*/
OctetString operator+(const OctetString& k1, const OctetString& k2) {
   secure_vector<uint8_t> out;
   out += k1.bits_of();
   out += k2.bits_of();
   return OctetString(out);
}

/*
* XOR Operation for OctetStrings
*/
OctetString operator^(const OctetString& k1, const OctetString& k2) {
   secure_vector<uint8_t> out(std::max(k1.length(), k2.length()));

   copy_mem(out.data(), k1.begin(), k1.length());
   xor_buf(out.data(), k2.begin(), k2.length());
   return OctetString(out);
}

}  // namespace Botan
/*
* Base32 Encoding and Decoding
* (C) 2018 Erwan Chaussy
* (C) 2018,2020,2025 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

class Base32 final {
   public:
      static std::string name() { return "base32"; }

      static constexpr size_t encoding_bytes_in() noexcept { return m_encoding_bytes_in; }

      static constexpr size_t encoding_bytes_out() noexcept { return m_encoding_bytes_out; }

      static constexpr size_t decoding_bytes_in() noexcept { return m_encoding_bytes_out; }

      static constexpr size_t decoding_bytes_out() noexcept { return m_encoding_bytes_in; }

      static constexpr size_t bits_consumed() noexcept { return m_encoding_bits; }

      static constexpr size_t remaining_bits_before_padding() noexcept { return m_remaining_bits_before_padding; }

      static constexpr size_t encode_max_output(size_t input_length) {
         const size_t encoding_blocks = round_up(input_length, m_encoding_bytes_in) / m_encoding_bytes_in;
         return mul_or_throw(encoding_blocks, m_encoding_bytes_out, "Input too large to base32 encode");
      }

      static constexpr size_t decode_max_output(size_t input_length) {
         // Divide before multiply to avoid overflow; round_up makes the division exact.
         return (round_up(input_length, m_encoding_bytes_out) / m_encoding_bytes_out) * m_encoding_bytes_in;
      }

      static void encode(char out[8], const uint8_t in[5]) noexcept;

      static uint8_t lookup_binary_value(char input) noexcept;

      static bool check_bad_char(uint8_t bin, char input, bool ignore_ws);

      static void decode(uint8_t* out_ptr, const uint8_t decode_buf[8]) {
         out_ptr[0] = (decode_buf[0] << 3) | (decode_buf[1] >> 2);
         out_ptr[1] = (decode_buf[1] << 6) | (decode_buf[2] << 1) | (decode_buf[3] >> 4);
         out_ptr[2] = (decode_buf[3] << 4) | (decode_buf[4] >> 1);
         out_ptr[3] = (decode_buf[4] << 7) | (decode_buf[5] << 2) | (decode_buf[6] >> 3);
         out_ptr[4] = (decode_buf[6] << 5) | decode_buf[7];
      }

      static size_t bytes_to_remove(size_t final_truncate) {
         return (final_truncate > 0) ? (final_truncate / 2) + 1 : 0;
      }

   private:
      static constexpr size_t m_encoding_bits = 5;
      static constexpr size_t m_remaining_bits_before_padding = 6;

      static constexpr size_t m_encoding_bytes_in = 5;
      static constexpr size_t m_encoding_bytes_out = 8;
};

namespace {

uint64_t lookup_base32_char(uint64_t x) {
   uint64_t r = x;
   r += swar_lt<uint64_t>(x, 0x1a1a1a1a1a1a1a1a) & 0x2929292929292929;
   r += 0x1818181818181818;

   return r;
}

}  // namespace

//static
void Base32::encode(char out[8], const uint8_t in[5]) noexcept {
   const uint8_t b0 = (in[0] & 0xF8) >> 3;
   const uint8_t b1 = ((in[0] & 0x07) << 2) | (in[1] >> 6);
   const uint8_t b2 = ((in[1] & 0x3E) >> 1);
   const uint8_t b3 = ((in[1] & 0x01) << 4) | (in[2] >> 4);
   const uint8_t b4 = ((in[2] & 0x0F) << 1) | (in[3] >> 7);
   const uint8_t b5 = ((in[3] & 0x7C) >> 2);
   const uint8_t b6 = ((in[3] & 0x03) << 3) | (in[4] >> 5);
   const uint8_t b7 = in[4] & 0x1F;

   auto b = lookup_base32_char(make_uint64(b0, b1, b2, b3, b4, b5, b6, b7));

   out[0] = static_cast<char>(get_byte<0>(b));
   out[1] = static_cast<char>(get_byte<1>(b));
   out[2] = static_cast<char>(get_byte<2>(b));
   out[3] = static_cast<char>(get_byte<3>(b));
   out[4] = static_cast<char>(get_byte<4>(b));
   out[5] = static_cast<char>(get_byte<5>(b));
   out[6] = static_cast<char>(get_byte<6>(b));
   out[7] = static_cast<char>(get_byte<7>(b));
}

//static
uint8_t Base32::lookup_binary_value(char input) noexcept {
   const uint8_t c = static_cast<uint8_t>(input);

   const auto is_alpha_upper = CT::Mask<uint8_t>::is_within_range(c, uint8_t('A'), uint8_t('Z'));
   const auto is_decimal = CT::Mask<uint8_t>::is_within_range(c, uint8_t('2'), uint8_t('7'));

   const auto is_equal = CT::Mask<uint8_t>::is_equal(c, uint8_t('='));
   const auto is_whitespace =
      CT::Mask<uint8_t>::is_any_of(c, {uint8_t(' '), uint8_t('\t'), uint8_t('\n'), uint8_t('\r')});

   const uint8_t c_upper = c - uint8_t('A');
   const uint8_t c_decim = c - uint8_t('2') + 26;

   uint8_t ret = 0xFF;  // default value

   ret = is_alpha_upper.select(c_upper, ret);
   ret = is_decimal.select(c_decim, ret);
   ret = is_equal.select(0x81, ret);
   ret = is_whitespace.select(0x80, ret);

   return ret;
}

//static
bool Base32::check_bad_char(uint8_t bin, char input, bool ignore_ws) {
   if(bin <= 0x1F) {
      return true;
   } else if(!(bin == 0x81 || (bin == 0x80 && ignore_ws))) {
      throw Invalid_Argument(fmt("base32_decode: invalid character '{}'", format_char_for_display(input)));
   }
   return false;
}

}  // namespace

size_t base32_encode(char out[], const uint8_t in[], size_t input_length, size_t& input_consumed, bool final_inputs) {
   return base_encode(Base32(), out, in, input_length, input_consumed, final_inputs);
}

std::string base32_encode(const uint8_t input[], size_t input_length) {
   return base_encode_to_string(Base32(), input, input_length);
}

size_t base32_decode(
   uint8_t out[], const char in[], size_t input_length, size_t& input_consumed, bool final_inputs, bool ignore_ws) {
   return base_decode(Base32(), out, in, input_length, input_consumed, final_inputs, ignore_ws);
}

size_t base32_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws) {
   return base_decode_full(Base32(), output, input, input_length, ignore_ws);
}

size_t base32_decode(uint8_t output[], std::string_view input, bool ignore_ws) {
   return base32_decode(output, input.data(), input.length(), ignore_ws);
}

secure_vector<uint8_t> base32_decode(const char input[], size_t input_length, bool ignore_ws) {
   return base_decode_to_vec<secure_vector<uint8_t>>(Base32(), input, input_length, ignore_ws);
}

secure_vector<uint8_t> base32_decode(std::string_view input, bool ignore_ws) {
   return base32_decode(input.data(), input.size(), ignore_ws);
}

size_t base32_encode_max_output(size_t input_length) {
   return Base32::encode_max_output(input_length);
}

size_t base32_decode_max_output(size_t input_length) {
   return Base32::decode_max_output(input_length);
}

}  // namespace Botan
/*
* Base64 Encoding and Decoding
* (C) 2010,2015,2020 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

class Base64 final {
   public:
      static std::string name() { return "base64"; }

      static constexpr size_t encoding_bytes_in() noexcept { return m_encoding_bytes_in; }

      static constexpr size_t encoding_bytes_out() noexcept { return m_encoding_bytes_out; }

      static constexpr size_t decoding_bytes_in() noexcept { return m_encoding_bytes_out; }

      static constexpr size_t decoding_bytes_out() noexcept { return m_encoding_bytes_in; }

      static constexpr size_t bits_consumed() noexcept { return m_encoding_bits; }

      static constexpr size_t remaining_bits_before_padding() noexcept { return m_remaining_bits_before_padding; }

      static constexpr size_t encode_max_output(size_t input_length) {
         const size_t encoding_blocks = round_up(input_length, m_encoding_bytes_in) / m_encoding_bytes_in;
         return mul_or_throw(encoding_blocks, m_encoding_bytes_out, "Input too large to base64 encode");
      }

      static constexpr size_t decode_max_output(size_t input_length) {
         // Divide before multiply to avoid overflow; round_up makes the division exact.
         return (round_up(input_length, m_encoding_bytes_out) / m_encoding_bytes_out) * m_encoding_bytes_in;
      }

      static void encode(char out[4], const uint8_t in[3]) noexcept;

      static uint8_t lookup_binary_value(char input) noexcept;

      static bool check_bad_char(uint8_t bin, char input, bool ignore_ws);

      static void decode(uint8_t* out_ptr, const uint8_t decode_buf[4]) {
         out_ptr[0] = (decode_buf[0] << 2) | (decode_buf[1] >> 4);
         out_ptr[1] = (decode_buf[1] << 4) | (decode_buf[2] >> 2);
         out_ptr[2] = (decode_buf[2] << 6) | decode_buf[3];
      }

      static size_t bytes_to_remove(size_t final_truncate) { return final_truncate; }

   private:
      static constexpr size_t m_encoding_bits = 6;
      static constexpr size_t m_remaining_bits_before_padding = 8;

      static constexpr size_t m_encoding_bytes_in = 3;
      static constexpr size_t m_encoding_bytes_out = 4;
};

uint32_t lookup_base64_chars(uint32_t x32) {
   /*
   * The basic insight of this approach is that our goal is computing
   * f(x) = y where x is in [0,63) and y is the correct base64 encoding.
   *
   * Instead of doing this directly, we compute
   * offset(x) such that f(x) = x + offset(x)
   *
   * This is described in
   * http://0x80.pl/notesen/2016-01-12-sse-base64-encoding.html#improved-version
   *
   * Here we do a SWAR (simd within a register) implementation of Wojciech's lookup_version2_swar
   */

   uint32_t r = x32 + 0x41414141;

   r += (~swar_lt<uint32_t>(x32, 0x1A1A1A1A)) & 0x06060606;
   r -= (~swar_lt<uint32_t>(x32, 0x34343434)) & 0x4B4B4B4B;
   r -= (~swar_lt<uint32_t>(x32, 0x3E3E3E3E)) & 0x0F0F0F0F;
   r += (~swar_lt<uint32_t>(x32, 0x3F3F3F3F)) & 0x03030303;

   return r;
}

//static
void Base64::encode(char out[4], const uint8_t in[3]) noexcept {
   const uint32_t b0 = (in[0] & 0xFC) >> 2;
   const uint32_t b1 = ((in[0] & 0x03) << 4) | (in[1] >> 4);
   const uint32_t b2 = ((in[1] & 0x0F) << 2) | (in[2] >> 6);
   const uint32_t b3 = in[2] & 0x3F;

   const uint32_t z = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;

   const uint32_t b64 = lookup_base64_chars(z);

   out[0] = static_cast<char>(get_byte<0>(b64));
   out[1] = static_cast<char>(get_byte<1>(b64));
   out[2] = static_cast<char>(get_byte<2>(b64));
   out[3] = static_cast<char>(get_byte<3>(b64));
}

//static
uint8_t Base64::lookup_binary_value(char input) noexcept {
   auto has_zero_byte = [](uint64_t v) { return ((v - 0x0101010101010101) & ~(v) & 0x8080808080808080); };

   // Assumes each byte is either 0x00 or 0x80
   auto index_of_first_set_byte = [](uint64_t v) {
      return ((((v - 1) & 0x0101010101010101) * 0x0101010101010101) >> 56) - 1;
   };

   constexpr uint64_t lo = 0x0101010101010101;

   const uint8_t x = static_cast<uint8_t>(input);

   const uint64_t x8 = x * lo;

   // Defines the valid ASCII ranges of base64, except the special chars (below)
   constexpr uint64_t val_l = make_uint64(0, 0, 0, 0, 0, 'A', 'a', '0');
   constexpr uint64_t val_u = make_uint64(0, 0, 0, 0, 0, 26, 26, 10);

   // If x is in one of the ranges return a mask. Otherwise we xor in at the
   // high word which will be our invalid marker
   auto v_mask = swar_in_range<uint64_t>(x8, val_l, val_u) ^ 0x80000000;

   // This is the offset added to x to get the value
   const uint64_t val_v = 0xbfb904 ^ (0xFF000000 - (x << 24));

   const uint8_t z = x + static_cast<uint8_t>(val_v >> (8 * index_of_first_set_byte(v_mask)));

   // Valid base64 special characters, and some whitespace chars
   constexpr uint64_t specials_i = make_uint64(0, '+', '/', '=', ' ', '\n', '\t', '\r');

   const uint64_t specials_v = 0x3e3f8180808080 ^ (static_cast<uint64_t>(z) << 56);

   const uint64_t smask = has_zero_byte(x8 ^ specials_i) ^ 0x8000000000000000;

   return static_cast<uint8_t>(specials_v >> (8 * index_of_first_set_byte(smask)));
}

//static
bool Base64::check_bad_char(uint8_t bin, char input, bool ignore_ws) {
   if(bin <= 0x3F) {
      return true;
   } else if(!(bin == 0x81 || (bin == 0x80 && ignore_ws))) {
      throw Invalid_Argument(fmt("base64_decode: invalid character '{}'", format_char_for_display(input)));
   }
   return false;
}

}  // namespace

size_t base64_encode(char out[], const uint8_t in[], size_t input_length, size_t& input_consumed, bool final_inputs) {
   return base_encode(Base64(), out, in, input_length, input_consumed, final_inputs);
}

std::string base64_encode(const uint8_t input[], size_t input_length) {
   return base_encode_to_string(Base64(), input, input_length);
}

size_t base64_decode(
   uint8_t out[], const char in[], size_t input_length, size_t& input_consumed, bool final_inputs, bool ignore_ws) {
   return base_decode(Base64(), out, in, input_length, input_consumed, final_inputs, ignore_ws);
}

size_t base64_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws) {
   return base_decode_full(Base64(), output, input, input_length, ignore_ws);
}

size_t base64_decode(uint8_t output[], std::string_view input, bool ignore_ws) {
   return base64_decode(output, input.data(), input.length(), ignore_ws);
}

size_t base64_decode(std::span<uint8_t> output, std::string_view input, bool ignore_ws) {
   if(output.size() < base64_decode_max_output(input.size())) {
      throw Invalid_Argument("base64_decode: output buffer is too short");
   }
   return base64_decode(output.data(), input.data(), input.length(), ignore_ws);
}

secure_vector<uint8_t> base64_decode(const char input[], size_t input_length, bool ignore_ws) {
   return base_decode_to_vec<secure_vector<uint8_t>>(Base64(), input, input_length, ignore_ws);
}

secure_vector<uint8_t> base64_decode(std::string_view input, bool ignore_ws) {
   return base64_decode(input.data(), input.size(), ignore_ws);
}

size_t base64_encode_max_output(size_t input_length) {
   return Base64::encode_max_output(input_length);
}

size_t base64_decode_max_output(size_t input_length) {
   return Base64::decode_max_output(input_length);
}

}  // namespace Botan
/*
* BLAKE2b
* (C) 2016 cynecx
* (C) 2017 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <array>

namespace Botan {

namespace {

constexpr std::array<uint64_t, 8> blake2b_IV{0x6a09e667f3bcc908,
                                             0xbb67ae8584caa73b,
                                             0x3c6ef372fe94f82b,
                                             0xa54ff53a5f1d36f1,
                                             0x510e527fade682d1,
                                             0x9b05688c2b3e6c1f,
                                             0x1f83d9abfb41bd6b,
                                             0x5be0cd19137e2179};

}  // namespace

BLAKE2b::BLAKE2b(size_t output_bits) : m_output_bits(output_bits), m_H(blake2b_IV.size()), m_T(), m_F(), m_key_size(0) {
   if(output_bits == 0 || output_bits > 512 || output_bits % 8 != 0) {
      throw Invalid_Argument("Bad output bits size for BLAKE2b");
   }

   state_init();
}

void BLAKE2b::state_init() {
   copy_mem(m_H.data(), blake2b_IV.data(), blake2b_IV.size());
   m_H[0] ^= (0x01010000 | (static_cast<uint8_t>(m_key_size) << 8) | static_cast<uint8_t>(output_length()));
   m_T[0] = m_T[1] = 0;
   m_F = 0;

   m_buffer.clear();
   if(m_key_size > 0) {
      m_buffer.append(m_padded_key_buffer);
   }
}

namespace {

BOTAN_FORCE_INLINE void G(uint64_t& a, uint64_t& b, uint64_t& c, uint64_t& d, uint64_t M0, uint64_t M1) {
   a = a + b + M0;
   d = rotr<32>(d ^ a);
   c = c + d;
   b = rotr<24>(b ^ c);
   a = a + b + M1;
   d = rotr<16>(d ^ a);
   c = c + d;
   b = rotr<63>(b ^ c);
}

template <size_t i0,
          size_t i1,
          size_t i2,
          size_t i3,
          size_t i4,
          size_t i5,
          size_t i6,
          size_t i7,
          size_t i8,
          size_t i9,
          size_t iA,
          size_t iB,
          size_t iC,
          size_t iD,
          size_t iE,
          size_t iF>
BOTAN_FORCE_INLINE void ROUND(uint64_t* v, const uint64_t* M) {
   G(v[0], v[4], v[8], v[12], M[i0], M[i1]);
   G(v[1], v[5], v[9], v[13], M[i2], M[i3]);
   G(v[2], v[6], v[10], v[14], M[i4], M[i5]);
   G(v[3], v[7], v[11], v[15], M[i6], M[i7]);
   G(v[0], v[5], v[10], v[15], M[i8], M[i9]);
   G(v[1], v[6], v[11], v[12], M[iA], M[iB]);
   G(v[2], v[7], v[8], v[13], M[iC], M[iD]);
   G(v[3], v[4], v[9], v[14], M[iE], M[iF]);
}

}  // namespace

void BLAKE2b::compress(const uint8_t* input, size_t blocks, uint64_t increment) {
   for(size_t b = 0; b != blocks; ++b) {
      m_T[0] += increment;
      if(m_T[0] < increment) {
         m_T[1]++;
      }

      uint64_t M[16];
      uint64_t v[16];
      load_le(M, input, 16);

      input += BLAKE2B_BLOCKBYTES;

      for(size_t i = 0; i < 8; i++) {
         v[i] = m_H[i];
      }
      for(size_t i = 0; i != 8; ++i) {
         v[i + 8] = blake2b_IV[i];
      }

      v[12] ^= m_T[0];
      v[13] ^= m_T[1];
      v[14] ^= m_F;

      ROUND<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>(v, M);
      ROUND<14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3>(v, M);
      ROUND<11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4>(v, M);
      ROUND<7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8>(v, M);
      ROUND<9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13>(v, M);
      ROUND<2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9>(v, M);
      ROUND<12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11>(v, M);
      ROUND<13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10>(v, M);
      ROUND<6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5>(v, M);
      ROUND<10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0>(v, M);
      ROUND<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>(v, M);
      ROUND<14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3>(v, M);

      for(size_t i = 0; i < 8; i++) {
         m_H[i] ^= v[i] ^ v[i + 8];
      }
   }
}

void BLAKE2b::add_data(std::span<const uint8_t> input) {
   BufferSlicer in(input);

   while(!in.empty()) {
      if(const auto one_block = m_buffer.handle_unaligned_data(in)) {
         compress(one_block->data(), 1, BLAKE2B_BLOCKBYTES);
      }

      if(m_buffer.in_alignment()) {
         const auto [aligned_data, full_blocks] = m_buffer.aligned_data_to_process(in);
         if(full_blocks > 0) {
            compress(aligned_data.data(), full_blocks, BLAKE2B_BLOCKBYTES);
         }
      }
   }
}

void BLAKE2b::final_result(std::span<uint8_t> output) {
   const auto pos = m_buffer.elements_in_buffer();
   m_buffer.fill_up_with_zeros();

   m_F = 0xFFFFFFFFFFFFFFFF;
   compress(m_buffer.consume().data(), 1, pos);
   copy_out_le(output.first(output_length()), m_H);
   state_init();
}

Key_Length_Specification BLAKE2b::key_spec() const {
   return Key_Length_Specification(1, 64);
}

std::string BLAKE2b::name() const {
   return fmt("BLAKE2b({})", m_output_bits);
}

std::unique_ptr<HashFunction> BLAKE2b::new_object() const {
   return std::make_unique<BLAKE2b>(m_output_bits);
}

std::unique_ptr<HashFunction> BLAKE2b::copy_state() const {
   return std::make_unique<BLAKE2b>(*this);
}

bool BLAKE2b::has_keying_material() const {
   return m_key_size > 0;
}

void BLAKE2b::key_schedule(std::span<const uint8_t> key) {
   BOTAN_ASSERT_NOMSG(key.size() <= m_buffer.size());

   m_key_size = key.size();
   m_padded_key_buffer.resize(m_buffer.size());

   if(m_padded_key_buffer.size() > m_key_size) {
      const size_t padding = m_padded_key_buffer.size() - m_key_size;
      clear_mem(m_padded_key_buffer.data() + m_key_size, padding);
   }

   copy_mem(m_padded_key_buffer.data(), key.data(), key.size());
   state_init();
}

void BLAKE2b::clear() {
   zeroise(m_H);
   m_buffer.clear();
   zeroise(m_padded_key_buffer);
   m_key_size = 0;
   state_init();
}

}  // namespace Botan
/*
* Block Ciphers
* (C) 2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <memory>
#include <utility>

#if defined(BOTAN_HAS_AES)
#endif

#if defined(BOTAN_HAS_ARIA)
#endif

#if defined(BOTAN_HAS_BLOWFISH)
#endif

#if defined(BOTAN_HAS_CAMELLIA)
#endif

#if defined(BOTAN_HAS_CAST_128)
#endif

#if defined(BOTAN_HAS_CASCADE)
#endif

#if defined(BOTAN_HAS_DES)
#endif

#if defined(BOTAN_HAS_GOST_28147_89)
#endif

#if defined(BOTAN_HAS_IDEA)
#endif

#if defined(BOTAN_HAS_KUZNYECHIK)
#endif

#if defined(BOTAN_HAS_LION)
#endif

#if defined(BOTAN_HAS_NOEKEON)
#endif

#if defined(BOTAN_HAS_SEED)
#endif

#if defined(BOTAN_HAS_SERPENT)
#endif

#if defined(BOTAN_HAS_SHACAL2)
#endif

#if defined(BOTAN_HAS_SM4)
#endif

#if defined(BOTAN_HAS_TWOFISH)
#endif

#if defined(BOTAN_HAS_THREEFISH_512)
#endif

#if defined(BOTAN_HAS_COMMONCRYPTO)
#endif

namespace Botan {

std::unique_ptr<BlockCipher> BlockCipher::create(std::string_view algo, std::string_view provider) {
#if defined(BOTAN_HAS_COMMONCRYPTO)
   if(provider.empty() || provider == "commoncrypto") {
      if(auto bc = make_commoncrypto_block_cipher(algo))
         return bc;

      if(!provider.empty())
         return nullptr;
   }
#endif

   // TODO: CryptoAPI
   // TODO: /dev/crypto

   // Only base providers from here on out
   if(provider.empty() == false && provider != "base") {
      return nullptr;
   }

#if defined(BOTAN_HAS_AES)
   if(algo == "AES-128") {
      return std::make_unique<AES_128>();
   }

   if(algo == "AES-192") {
      return std::make_unique<AES_192>();
   }

   if(algo == "AES-256") {
      return std::make_unique<AES_256>();
   }
#endif

#if defined(BOTAN_HAS_ARIA)
   if(algo == "ARIA-128") {
      return std::make_unique<ARIA_128>();
   }

   if(algo == "ARIA-192") {
      return std::make_unique<ARIA_192>();
   }

   if(algo == "ARIA-256") {
      return std::make_unique<ARIA_256>();
   }
#endif

#if defined(BOTAN_HAS_SERPENT)
   if(algo == "Serpent") {
      return std::make_unique<Serpent>();
   }
#endif

#if defined(BOTAN_HAS_SHACAL2)
   if(algo == "SHACAL2") {
      return std::make_unique<SHACAL2>();
   }
#endif

#if defined(BOTAN_HAS_TWOFISH)
   if(algo == "Twofish") {
      return std::make_unique<Twofish>();
   }
#endif

#if defined(BOTAN_HAS_THREEFISH_512)
   if(algo == "Threefish-512") {
      return std::make_unique<Threefish_512>();
   }
#endif

#if defined(BOTAN_HAS_BLOWFISH)
   if(algo == "Blowfish") {
      return std::make_unique<Blowfish>();
   }
#endif

#if defined(BOTAN_HAS_CAMELLIA)
   if(algo == "Camellia-128") {
      return std::make_unique<Camellia_128>();
   }

   if(algo == "Camellia-192") {
      return std::make_unique<Camellia_192>();
   }

   if(algo == "Camellia-256") {
      return std::make_unique<Camellia_256>();
   }
#endif

#if defined(BOTAN_HAS_DES)
   if(algo == "DES") {
      return std::make_unique<DES>();
   }

   if(algo == "TripleDES" || algo == "3DES" || algo == "DES-EDE") {
      return std::make_unique<TripleDES>();
   }
#endif

#if defined(BOTAN_HAS_NOEKEON)
   if(algo == "Noekeon") {
      return std::make_unique<Noekeon>();
   }
#endif

#if defined(BOTAN_HAS_CAST_128)
   if(algo == "CAST-128" || algo == "CAST5") {
      return std::make_unique<CAST_128>();
   }
#endif

#if defined(BOTAN_HAS_IDEA)
   if(algo == "IDEA") {
      return std::make_unique<IDEA>();
   }
#endif

#if defined(BOTAN_HAS_KUZNYECHIK)
   if(algo == "Kuznyechik") {
      return std::make_unique<Kuznyechik>();
   }
#endif

#if defined(BOTAN_HAS_SEED)
   if(algo == "SEED") {
      return std::make_unique<SEED>();
   }
#endif

#if defined(BOTAN_HAS_SM4)
   if(algo == "SM4") {
      return std::make_unique<SM4>();
   }
#endif

   const SCAN_Name req(algo);

#if defined(BOTAN_HAS_GOST_28147_89)
   if(req.algo_name() == "GOST-28147-89") {
      return std::make_unique<GOST_28147_89>(req.arg(0, "R3411_94_TestParam"));
   }
#endif

#if defined(BOTAN_HAS_CASCADE)
   if(req.algo_name() == "Cascade" && req.arg_count() == 2) {
      auto c1 = BlockCipher::create(req.arg(0));
      auto c2 = BlockCipher::create(req.arg(1));

      if(c1 && c2) {
         return std::make_unique<Cascade_Cipher>(std::move(c1), std::move(c2));
      }
   }
#endif

#if defined(BOTAN_HAS_LION)
   if(req.algo_name() == "Lion" && req.arg_count_between(2, 3)) {
      auto hash = HashFunction::create(req.arg(0));
      auto stream = StreamCipher::create(req.arg(1));

      if(hash && stream) {
         const size_t block_size = req.arg_as_integer(2, 1024);
         return std::make_unique<Lion>(std::move(hash), std::move(stream), block_size);
      }
   }
#endif

   BOTAN_UNUSED(req);
   BOTAN_UNUSED(provider);

   return nullptr;
}

//static
std::unique_ptr<BlockCipher> BlockCipher::create_or_throw(std::string_view algo, std::string_view provider) {
   if(auto bc = BlockCipher::create(algo, provider)) {
      return bc;
   }
   throw Lookup_Error("Block cipher", algo, provider);
}

std::vector<std::string> BlockCipher::providers(std::string_view algo) {
   return probe_providers_of<BlockCipher>(algo, {"base", "commoncrypto"});
}

}  // namespace Botan
/*
* ChaCha
* (C) 2014,2018,2023 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

namespace Botan {

namespace {

/*
* RFC 8439 defines ChaCha with 96-bit nonces by stealing one of the
* words used for the block counter. With 64-bit nonces, the block
* counter is also 64 bits and practically not exhaustible.
*/
constexpr uint64_t chacha_96bit_nonce_cap = uint64_t{1} << 38;

inline void chacha_quarter_round(uint32_t& a, uint32_t& b, uint32_t& c, uint32_t& d) {
   a += b;
   d ^= a;
   d = rotl<16>(d);
   c += d;
   b ^= c;
   b = rotl<12>(b);
   a += b;
   d ^= a;
   d = rotl<8>(d);
   c += d;
   b ^= c;
   b = rotl<7>(b);
}

/*
* Generate HChaCha cipher stream (for XChaCha IV setup)
*/
void hchacha(uint32_t output[8], const uint32_t input[16], size_t rounds) {
   BOTAN_ASSERT(rounds % 2 == 0, "Valid rounds");

   uint32_t x00 = input[0];
   uint32_t x01 = input[1];
   uint32_t x02 = input[2];
   uint32_t x03 = input[3];
   uint32_t x04 = input[4];
   uint32_t x05 = input[5];
   uint32_t x06 = input[6];
   uint32_t x07 = input[7];
   uint32_t x08 = input[8];
   uint32_t x09 = input[9];
   uint32_t x10 = input[10];
   uint32_t x11 = input[11];
   uint32_t x12 = input[12];
   uint32_t x13 = input[13];
   uint32_t x14 = input[14];
   uint32_t x15 = input[15];

   for(size_t i = 0; i != rounds / 2; ++i) {
      chacha_quarter_round(x00, x04, x08, x12);
      chacha_quarter_round(x01, x05, x09, x13);
      chacha_quarter_round(x02, x06, x10, x14);
      chacha_quarter_round(x03, x07, x11, x15);

      chacha_quarter_round(x00, x05, x10, x15);
      chacha_quarter_round(x01, x06, x11, x12);
      chacha_quarter_round(x02, x07, x08, x13);
      chacha_quarter_round(x03, x04, x09, x14);
   }

   output[0] = x00;
   output[1] = x01;
   output[2] = x02;
   output[3] = x03;
   output[4] = x12;
   output[5] = x13;
   output[6] = x14;
   output[7] = x15;
}

}  // namespace

ChaCha::ChaCha(size_t rounds) : m_rounds(rounds) {
   BOTAN_ARG_CHECK(m_rounds == 8 || m_rounds == 12 || m_rounds == 20, "ChaCha only supports 8, 12 or 20 rounds");
}

size_t ChaCha::parallelism() {
#if defined(BOTAN_HAS_CHACHA_AVX512)
   if(CPUID::has(CPUID::Feature::AVX512)) {
      return 16;
   }
#endif

#if defined(BOTAN_HAS_CHACHA_AVX2)
   if(CPUID::has(CPUID::Feature::AVX2)) {
      return 8;
   }
#endif

   return 4;
}

std::string ChaCha::provider() const {
#if defined(BOTAN_HAS_CHACHA_AVX512)
   if(auto feat = CPUID::check(CPUID::Feature::AVX512)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_CHACHA_AVX2)
   if(auto feat = CPUID::check(CPUID::Feature::AVX2)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_CHACHA_SIMD32)
   if(auto feat = CPUID::check(CPUID::Feature::SIMD_4X32)) {
      return *feat;
   }
#endif

   return "base";
}

void ChaCha::chacha(uint8_t output[], size_t output_blocks, uint32_t state[16], size_t rounds) {
   BOTAN_ASSERT(rounds % 2 == 0, "Valid rounds");

#if defined(BOTAN_HAS_CHACHA_AVX512)
   if(CPUID::has(CPUID::Feature::AVX512)) {
      while(output_blocks >= 16) {
         ChaCha::chacha_avx512_x16(output, state, rounds);
         output += 16 * 64;
         output_blocks -= 16;
      }
   }
#endif

#if defined(BOTAN_HAS_CHACHA_AVX2)
   if(CPUID::has(CPUID::Feature::AVX2)) {
      while(output_blocks >= 8) {
         ChaCha::chacha_avx2_x8(output, state, rounds);
         output += 8 * 64;
         output_blocks -= 8;
      }
   }
#endif

#if defined(BOTAN_HAS_CHACHA_SIMD32)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      while(output_blocks >= 4) {
         ChaCha::chacha_simd32_x4(output, state, rounds);
         output += 4 * 64;
         output_blocks -= 4;
      }
   }
#endif

   // TODO interleave rounds
   for(size_t i = 0; i != output_blocks; ++i) {
      uint32_t x00 = state[0];
      uint32_t x01 = state[1];
      uint32_t x02 = state[2];
      uint32_t x03 = state[3];
      uint32_t x04 = state[4];
      uint32_t x05 = state[5];
      uint32_t x06 = state[6];
      uint32_t x07 = state[7];
      uint32_t x08 = state[8];
      uint32_t x09 = state[9];
      uint32_t x10 = state[10];
      uint32_t x11 = state[11];
      uint32_t x12 = state[12];
      uint32_t x13 = state[13];
      uint32_t x14 = state[14];
      uint32_t x15 = state[15];

      for(size_t r = 0; r != rounds / 2; ++r) {
         chacha_quarter_round(x00, x04, x08, x12);
         chacha_quarter_round(x01, x05, x09, x13);
         chacha_quarter_round(x02, x06, x10, x14);
         chacha_quarter_round(x03, x07, x11, x15);

         chacha_quarter_round(x00, x05, x10, x15);
         chacha_quarter_round(x01, x06, x11, x12);
         chacha_quarter_round(x02, x07, x08, x13);
         chacha_quarter_round(x03, x04, x09, x14);
      }

      x00 += state[0];
      x01 += state[1];
      x02 += state[2];
      x03 += state[3];
      x04 += state[4];
      x05 += state[5];
      x06 += state[6];
      x07 += state[7];
      x08 += state[8];
      x09 += state[9];
      x10 += state[10];
      x11 += state[11];
      x12 += state[12];
      x13 += state[13];
      x14 += state[14];
      x15 += state[15];

      store_le(x00, output + 64 * i + 4 * 0);
      store_le(x01, output + 64 * i + 4 * 1);
      store_le(x02, output + 64 * i + 4 * 2);
      store_le(x03, output + 64 * i + 4 * 3);
      store_le(x04, output + 64 * i + 4 * 4);
      store_le(x05, output + 64 * i + 4 * 5);
      store_le(x06, output + 64 * i + 4 * 6);
      store_le(x07, output + 64 * i + 4 * 7);
      store_le(x08, output + 64 * i + 4 * 8);
      store_le(x09, output + 64 * i + 4 * 9);
      store_le(x10, output + 64 * i + 4 * 10);
      store_le(x11, output + 64 * i + 4 * 11);
      store_le(x12, output + 64 * i + 4 * 12);
      store_le(x13, output + 64 * i + 4 * 13);
      store_le(x14, output + 64 * i + 4 * 14);
      store_le(x15, output + 64 * i + 4 * 15);

      state[12]++;
      if(state[12] == 0) {
         state[13] += 1;
      }
   }
}

/*
* Combine cipher stream with message
*/
void ChaCha::cipher_bytes(const uint8_t in[], uint8_t out[], size_t length) {
   assert_key_material_set();

   if(m_iv_length == 12) {
      if(length > m_bytes_remaining) {
         throw Invalid_State("ChaCha 96-bit nonce keystream exhausted");
      }
      m_bytes_remaining -= length;
   }

   while(length >= m_buffer.size() - m_position) {
      const size_t available = m_buffer.size() - m_position;

      xor_buf(out, in, &m_buffer[m_position], available);
      chacha(m_buffer.data(), m_buffer.size() / 64, m_state.data(), m_rounds);

      length -= available;
      in += available;
      out += available;
      m_position = 0;
   }

   xor_buf(out, in, &m_buffer[m_position], length);

   m_position += length;
}

void ChaCha::generate_keystream(uint8_t out[], size_t length) {
   assert_key_material_set();

   if(m_iv_length == 12) {
      if(length > m_bytes_remaining) {
         throw Invalid_State("ChaCha 96-bit nonce keystream exhausted");
      }
      m_bytes_remaining -= length;
   }

   while(length >= m_buffer.size() - m_position) {
      const size_t available = m_buffer.size() - m_position;

      // TODO: this could write directly to the output buffer
      // instead of bouncing it through m_buffer first
      copy_mem(out, &m_buffer[m_position], available);
      chacha(m_buffer.data(), m_buffer.size() / 64, m_state.data(), m_rounds);

      length -= available;
      out += available;
      m_position = 0;
   }

   copy_mem(out, &m_buffer[m_position], length);

   m_position += length;
}

void ChaCha::initialize_state() {
   static const uint32_t TAU[] = {0x61707865, 0x3120646e, 0x79622d36, 0x6b206574};

   static const uint32_t SIGMA[] = {0x61707865, 0x3320646e, 0x79622d32, 0x6b206574};

   m_state[4] = m_key[0];
   m_state[5] = m_key[1];
   m_state[6] = m_key[2];
   m_state[7] = m_key[3];

   if(m_key.size() == 4) {
      m_state[0] = TAU[0];
      m_state[1] = TAU[1];
      m_state[2] = TAU[2];
      m_state[3] = TAU[3];

      m_state[8] = m_key[0];
      m_state[9] = m_key[1];
      m_state[10] = m_key[2];
      m_state[11] = m_key[3];
   } else {
      m_state[0] = SIGMA[0];
      m_state[1] = SIGMA[1];
      m_state[2] = SIGMA[2];
      m_state[3] = SIGMA[3];

      m_state[8] = m_key[4];
      m_state[9] = m_key[5];
      m_state[10] = m_key[6];
      m_state[11] = m_key[7];
   }

   m_state[12] = 0;
   m_state[13] = 0;
   m_state[14] = 0;
   m_state[15] = 0;

   m_position = 0;
}

bool ChaCha::has_keying_material() const {
   return !m_state.empty();
}

size_t ChaCha::buffer_size() const {
   return 64;
}

/*
* ChaCha Key Schedule
*/
void ChaCha::key_schedule(std::span<const uint8_t> key) {
   m_key.resize(key.size() / 4);
   load_le<uint32_t>(m_key.data(), key.data(), m_key.size());

   m_state.resize(16);

   const size_t chacha_block = 64;
   m_buffer.resize(parallelism() * chacha_block);

   set_iv(nullptr, 0);
}

size_t ChaCha::default_iv_length() const {
   return 24;
}

Key_Length_Specification ChaCha::key_spec() const {
   return Key_Length_Specification(16, 32, 16);
}

std::unique_ptr<StreamCipher> ChaCha::new_object() const {
   return std::make_unique<ChaCha>(m_rounds);
}

bool ChaCha::valid_iv_length(size_t iv_len) const {
   return (iv_len == 0 || iv_len == 8 || iv_len == 12 || iv_len == 24);
}

void ChaCha::set_iv_bytes(const uint8_t iv[], size_t length) {
   assert_key_material_set();

   if(!valid_iv_length(length)) {
      throw Invalid_IV_Length(name(), length);
   }

   initialize_state();

   if(length == 0) {
      // Treat zero length IV same as an all-zero IV
      m_state[14] = 0;
      m_state[15] = 0;
   } else if(length == 8) {
      m_state[14] = load_le<uint32_t>(iv, 0);
      m_state[15] = load_le<uint32_t>(iv, 1);
   } else if(length == 12) {
      m_state[13] = load_le<uint32_t>(iv, 0);
      m_state[14] = load_le<uint32_t>(iv, 1);
      m_state[15] = load_le<uint32_t>(iv, 2);
   } else if(length == 24) {
      m_state[12] = load_le<uint32_t>(iv, 0);
      m_state[13] = load_le<uint32_t>(iv, 1);
      m_state[14] = load_le<uint32_t>(iv, 2);
      m_state[15] = load_le<uint32_t>(iv, 3);

      secure_vector<uint32_t> hc(8);
      hchacha(hc.data(), m_state.data(), m_rounds);

      m_state[4] = hc[0];
      m_state[5] = hc[1];
      m_state[6] = hc[2];
      m_state[7] = hc[3];
      m_state[8] = hc[4];
      m_state[9] = hc[5];
      m_state[10] = hc[6];
      m_state[11] = hc[7];
      m_state[12] = 0;
      m_state[13] = 0;
      m_state[14] = load_le<uint32_t>(iv, 4);
      m_state[15] = load_le<uint32_t>(iv, 5);
   }

   m_iv_length = length;
   m_state13_post_iv = m_state[13];
   if(length == 12) {
      m_bytes_remaining = chacha_96bit_nonce_cap;
   }

   chacha(m_buffer.data(), m_buffer.size() / 64, m_state.data(), m_rounds);
   m_position = 0;
}

void ChaCha::clear() {
   zap(m_key);
   zap(m_state);
   zap(m_buffer);
   m_position = 0;
   m_iv_length = 0;
   m_state13_post_iv = 0;
   m_bytes_remaining = 0;
}

std::optional<uint64_t> ChaCha::remaining_keystream_bytes() const {
   if(!has_keying_material() || m_iv_length != 12) {
      return std::nullopt;
   }
   return m_bytes_remaining;
}

std::string ChaCha::name() const {
   return fmt("ChaCha({})", m_rounds);
}

void ChaCha::seek(uint64_t offset) {
   assert_key_material_set();

   const uint64_t block = offset / 64;

   if(m_iv_length == 12) {
      // 96 bit nonce implies a 32-bit counter; prevent seeking beyond that
      if((block >> 32) != 0) {
         throw Invalid_Argument("ChaCha::seek with 96-bit nonce limited to 2^32 blocks (256 GiB)");
      }
      m_state[12] = static_cast<uint32_t>(block);
      m_state[13] = m_state13_post_iv;
      m_bytes_remaining = chacha_96bit_nonce_cap - offset;
   } else {
      // 64-bit block counter spanning state words 12 and 13.
      m_state[12] = static_cast<uint32_t>(block);
      m_state[13] = m_state13_post_iv + static_cast<uint32_t>(block >> 32);
   }

   chacha(m_buffer.data(), m_buffer.size() / 64, m_state.data(), m_rounds);
   m_position = offset % 64;
}
}  // namespace Botan
/*
* ChaCha20Poly1305 AEAD
* (C) 2014,2016,2018 Jack Lloyd
* (C) 2016 Daniel Neus, Rohde & Schwarz Cybersecurity
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

ChaCha20Poly1305_Mode::ChaCha20Poly1305_Mode() :
      m_chacha(StreamCipher::create("ChaCha")), m_poly1305(MessageAuthenticationCode::create("Poly1305")) {
   if(!m_chacha || !m_poly1305) {
      throw Algorithm_Not_Found("ChaCha20Poly1305");
   }
}

bool ChaCha20Poly1305_Mode::valid_nonce_length(size_t n) const {
   return (n == 8 || n == 12 || n == 24);
}

size_t ChaCha20Poly1305_Mode::update_granularity() const {
   return 1;
}

size_t ChaCha20Poly1305_Mode::ideal_granularity() const {
   return 128;
}

void ChaCha20Poly1305_Mode::clear() {
   m_chacha->clear();
   m_poly1305->clear();
   m_ad.clear();
   reset();
}

void ChaCha20Poly1305_Mode::reset() {
   m_ctext_len = 0;
   m_nonce_len = 0;
}

bool ChaCha20Poly1305_Mode::has_keying_material() const {
   return m_chacha->has_keying_material();
}

void ChaCha20Poly1305_Mode::key_schedule(std::span<const uint8_t> key) {
   m_chacha->set_key(key);
   // Clear any per-message state; AD is preserved per AEAD contract
   // (ChaCha20Poly1305 advertises associated_data_requires_key() == false).
   reset();
}

void ChaCha20Poly1305_Mode::set_associated_data_n(size_t idx, std::span<const uint8_t> ad) {
   BOTAN_ARG_CHECK(idx == 0, "ChaCha20Poly1305: cannot handle non-zero index in set_associated_data_n");
   if(m_ctext_len > 0 || m_nonce_len > 0) {
      throw Invalid_State("Cannot set AD for ChaCha20Poly1305 while processing a message");
   }
   m_ad.assign(ad.begin(), ad.end());
}

void ChaCha20Poly1305_Mode::update_len(uint64_t len) {
   uint8_t len8[8] = {0};
   store_le(len, len8);
   m_poly1305->update(len8, 8);
}

void ChaCha20Poly1305_Mode::start_msg(const uint8_t nonce[], size_t nonce_len) {
   BOTAN_STATE_CHECK(m_nonce_len == 0);

   if(!valid_nonce_length(nonce_len)) {
      throw Invalid_IV_Length(name(), nonce_len);
   }

   m_ctext_len = 0;
   m_nonce_len = nonce_len;

   m_chacha->set_iv(nonce, nonce_len);

   uint8_t first_block[64];
   m_chacha->write_keystream(first_block, sizeof(first_block));

   m_poly1305->set_key(first_block, 32);
   // Remainder of first block is discarded
   secure_scrub_memory(first_block, sizeof(first_block));

   m_poly1305->update(m_ad);

   if(cfrg_version()) {
      if(m_ad.size() % 16 != 0) {
         const uint8_t zeros[16] = {0};
         m_poly1305->update(zeros, 16 - m_ad.size() % 16);
      }
   } else {
      update_len(m_ad.size());
   }
}

size_t ChaCha20Poly1305_Encryption::output_length(size_t input_length) const {
   return add_or_throw(input_length, tag_size(), "ChaCha20Poly1305 input too large");
}

size_t ChaCha20Poly1305_Encryption::process_msg(uint8_t buf[], size_t sz) {
   BOTAN_STATE_CHECK(m_nonce_len > 0);
   m_chacha->cipher1(buf, sz);
   m_poly1305->update(buf, sz);  // poly1305 of ciphertext
   m_ctext_len += sz;

   // RFC 8439 limits messages to 2^38-64 bytes
   constexpr uint64_t MAX_CHACHA20POLY1305_INPUT = (static_cast<uint64_t>(1) << 38) - 64;
   if(cfrg_version() && m_ctext_len > MAX_CHACHA20POLY1305_INPUT) {
      throw Invalid_State("ChaCha20Poly1305 message length limit exceeded");
   }

   return sz;
}

void ChaCha20Poly1305_Encryption::finish_msg(secure_vector<uint8_t>& buffer, size_t offset) {
   BOTAN_STATE_CHECK(m_nonce_len > 0);
   BOTAN_ARG_CHECK(buffer.size() >= offset, "Offset is out of range");
   update(buffer, offset);
   if(cfrg_version()) {
      if(m_ctext_len % 16 != 0) {
         const uint8_t zeros[16] = {0};
         const size_t padding = static_cast<size_t>(16 - m_ctext_len % 16);
         m_poly1305->update(zeros, padding);
      }
      update_len(m_ad.size());
   }
   update_len(m_ctext_len);

   const auto new_size = checked_add(buffer.size(), tag_size());
   if(!new_size.has_value()) {
      throw Invalid_State("ChaCha20Poly1305 message length limit exceeded");
   }
   buffer.resize(new_size.value());
   m_poly1305->final(&buffer[buffer.size() - tag_size()]);
   m_ctext_len = 0;
   m_nonce_len = 0;
}

size_t ChaCha20Poly1305_Decryption::output_length(size_t input_length) const {
   BOTAN_ARG_CHECK(input_length >= tag_size(), "Message too short to be valid");
   return input_length - tag_size();
}

size_t ChaCha20Poly1305_Decryption::process_msg(uint8_t buf[], size_t sz) {
   BOTAN_STATE_CHECK(m_nonce_len > 0);
   m_poly1305->update(buf, sz);  // poly1305 of ciphertext
   m_chacha->cipher1(buf, sz);
   m_ctext_len += sz;

   constexpr uint64_t MAX_CHACHA20POLY1305_INPUT = (static_cast<uint64_t>(1) << 38) - 64;
   if(cfrg_version() && m_ctext_len > MAX_CHACHA20POLY1305_INPUT) {
      throw Invalid_State("ChaCha20Poly1305 message length limit exceeded");
   }

   return sz;
}

void ChaCha20Poly1305_Decryption::finish_msg(secure_vector<uint8_t>& buffer, size_t offset) {
   BOTAN_STATE_CHECK(m_nonce_len > 0);
   BOTAN_ARG_CHECK(buffer.size() >= offset, "Offset is out of range");
   const size_t sz = buffer.size() - offset;
   uint8_t* buf = buffer.data() + offset;

   BOTAN_ARG_CHECK(sz >= tag_size(), "input did not include the tag");

   const size_t remaining = sz - tag_size();

   if(remaining > 0) {
      // Route through process_msg so the RFC 8439 length limit is enforced for
      // one-shot decryption too (finish() calls finish_msg() directly).
      process_msg(buf, remaining);
   }

   if(cfrg_version()) {
      if(m_ctext_len % 16 != 0) {
         const uint8_t zeros[16] = {0};
         const size_t padding = static_cast<size_t>(16 - m_ctext_len % 16);
         m_poly1305->update(zeros, padding);
      }
      update_len(m_ad.size());
   }

   update_len(m_ctext_len);

   uint8_t mac[16];
   m_poly1305->final(mac);

   const uint8_t* included_tag = &buf[remaining];

   m_ctext_len = 0;
   m_nonce_len = 0;

   if(!CT::is_equal(mac, included_tag, tag_size()).as_bool()) {
      clear_mem(std::span{buffer}.subspan(offset, remaining));
      throw Invalid_Authentication_Tag("ChaCha20Poly1305 tag check failed");
   }
   buffer.resize(offset + remaining);
}

}  // namespace Botan
/*
* Runtime CPU detection
* (C) 2009,2010,2013,2017,2023 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_OS_UTILS)
#endif

namespace Botan {

#if !defined(BOTAN_HAS_CPUID_DETECTION)
uint32_t CPUFeature::as_u32() const {
   throw Invalid_State("CPUFeature invalid bit");
}

std::optional<CPUFeature> CPUFeature::from_string(std::string_view) {
   return {};
}

std::string CPUFeature::to_string() const {
   throw Invalid_State("CPUFeature invalid bit");
}
#endif

//static
std::string CPUID::to_string() {
   std::vector<std::string> flags;

   const uint32_t bitset = state().bitset();

   for(size_t i = 0; i != 32; ++i) {
      const uint32_t b = static_cast<uint32_t>(1) << i;
      if((bitset & b) == b) {
         // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
         flags.push_back(CPUFeature(static_cast<CPUFeature::Bit>(b)).to_string());
      }
   }

   return string_join(flags, ' ');
}

//static
void CPUID::initialize() {
   state() = CPUID_Data();
}

#if defined(BOTAN_HAS_CPUID_DETECTION)

namespace {

uint32_t cleared_cpuid_bits() {
   uint32_t cleared = 0;

   #if defined(BOTAN_HAS_OS_UTILS)
   std::string clear_cpuid_env;
   if(OS::read_env_variable(clear_cpuid_env, "BOTAN_CLEAR_CPUID")) {
      for(const auto& cpuid : split_on(clear_cpuid_env, ',')) {
         if(auto bit = CPUID::bit_from_string(cpuid)) {
            cleared |= bit->as_u32();
         }
      }
   }
   #endif

   return cleared;
}

}  // namespace

#endif

CPUID::CPUID_Data::CPUID_Data() {
   // NOLINTBEGIN(*-prefer-member-initializer)
#if defined(BOTAN_HAS_CPUID_DETECTION)
   m_processor_features = detect_cpu_features(~cleared_cpuid_bits());
#else
   m_processor_features = 0;
#endif
   // NOLINTEND(*-prefer-member-initializer)
}

std::optional<CPUFeature> CPUID::bit_from_string(std::string_view tok) {
   return CPUFeature::from_string(tok);
}

}  // namespace Botan
/*
* Runtime CPU detection for Aarch64
* (C) 2009,2010,2013,2017,2020,2024 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <optional>

#if defined(BOTAN_HAS_OS_UTILS)
#endif

#if defined(BOTAN_TARGET_OS_HAS_SYSCTLBYNAME)
   #include <sys/sysctl.h>
   #include <sys/types.h>
#endif

namespace Botan {

namespace {

std::optional<uint32_t> aarch64_feat_via_auxval(uint32_t allowed) {
#if defined(BOTAN_HAS_OS_UTILS)

   if(auto auxval = OS::get_auxval_hwcap()) {
      uint32_t feat = 0;

      /*
      * On systems with getauxval these bits should normally be defined
      * in bits/auxv.h but some buggy? glibc installs seem to miss them.
      * These following values are all fixed, for the Linux ELF format,
      * so we just hardcode them in ARM_hwcap_bit enum.
      */
      enum class ARM_hwcap_bit : uint64_t /* NOLINT(*-enum-size) */ {
         NEON_bit = (1 << 1),
         AES_bit = (1 << 3),
         PMULL_bit = (1 << 4),
         SHA1_bit = (1 << 5),
         SHA2_bit = (1 << 6),
         SHA3_bit = (1 << 17),
         SM3_bit = (1 << 18),
         SM4_bit = (1 << 19),
         SHA2_512_bit = (1 << 21),
         SVE_bit = (1 << 22),
      };

      const auto hwcap = auxval->first;

      feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::NEON_bit, CPUFeature::Bit::NEON, allowed);

      if((feat & CPUFeature::Bit::NEON) == CPUFeature::Bit::NEON) {
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::AES_bit, CPUFeature::Bit::AES, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::PMULL_bit, CPUFeature::Bit::PMULL, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SHA1_bit, CPUFeature::Bit::SHA1, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SHA2_bit, CPUFeature::Bit::SHA2, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SHA3_bit, CPUFeature::Bit::SHA3, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SM3_bit, CPUFeature::Bit::SM3, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SM4_bit, CPUFeature::Bit::SM4, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SHA2_512_bit, CPUFeature::Bit::SHA2_512, allowed);
         feat |= CPUID::if_set(hwcap, ARM_hwcap_bit::SVE_bit, CPUFeature::Bit::SVE, allowed);
      }

      return feat;
   }
#else
   BOTAN_UNUSED(allowed);
#endif

   return {};
}

std::optional<uint32_t> aarch64_feat_using_mac_api(uint32_t allowed) {
#if defined(BOTAN_TARGET_OS_IS_IOS) || defined(BOTAN_TARGET_OS_IS_MACOS)
   uint32_t feat = 0;

   auto sysctlbyname_has_feature = [](const char* feature_name) -> bool {
      unsigned int feature = 0;
      size_t size = sizeof(feature);
      if(::sysctlbyname(feature_name, &feature, &size, nullptr, 0) == 0) {
         return (feature == 1);
      } else {
         return false;
      }
   };

   // All 64-bit Apple ARM chips have NEON, AES, and SHA support
   feat |= CPUFeature::Bit::NEON & allowed;
   if((feat & CPUFeature::Bit::NEON) == CPUFeature::Bit::NEON) {
      feat |= CPUFeature::Bit::AES & allowed;
      feat |= CPUFeature::Bit::PMULL & allowed;
      feat |= CPUFeature::Bit::SHA1 & allowed;
      feat |= CPUFeature::Bit::SHA2 & allowed;

      if(sysctlbyname_has_feature("hw.optional.armv8_2_sha3")) {
         feat |= CPUFeature::Bit::SHA3 & allowed;
      }
      if(sysctlbyname_has_feature("hw.optional.armv8_2_sha512")) {
         feat |= CPUFeature::Bit::SHA2_512 & allowed;
      }
   }

   return feat;
#else
   BOTAN_UNUSED(allowed);
   return {};
#endif
}

std::optional<uint32_t> aarch64_feat_using_instr_probe(uint32_t allowed) {
#if defined(BOTAN_USE_GCC_INLINE_ASM) && defined(BOTAN_HAS_OS_UTILS)

   // NOLINTBEGIN(*-no-assembler)

   /*
   No getauxval API available, fall back on probe functions.
   NEON registers v0-v7 are caller saved in Aarch64
   */

   auto neon_probe = []() noexcept -> int {
      asm("and v0.16b, v0.16b, v0.16b");
      return 1;
   };
   auto aes_probe = []() noexcept -> int {
      asm(".word 0x4e284800");
      return 1;
   };
   auto pmull_probe = []() noexcept -> int {
      asm(".word 0x0ee0e000");
      return 1;
   };
   auto sha1_probe = []() noexcept -> int {
      asm(".word 0x5e280800");
      return 1;
   };
   auto sha2_probe = []() noexcept -> int {
      asm(".word 0x5e282800");
      return 1;
   };
   auto sha512_probe = []() noexcept -> int {
      asm(".long 0xcec08000");
      return 1;
   };

   // NOLINTEND(*-no-assembler)

   uint32_t feat = 0;
   if((allowed & CPUFeature::Bit::NEON) == CPUFeature::Bit::NEON) {
      if(OS::run_cpu_instruction_probe(neon_probe) == 1) {
         feat |= CPUFeature::Bit::NEON;

         if(OS::run_cpu_instruction_probe(aes_probe) == 1) {
            feat |= CPUFeature::Bit::AES & allowed;
         }
         if(OS::run_cpu_instruction_probe(pmull_probe) == 1) {
            feat |= CPUFeature::Bit::PMULL & allowed;
         }
         if(OS::run_cpu_instruction_probe(sha1_probe) == 1) {
            feat |= CPUFeature::Bit::SHA1 & allowed;
         }
         if(OS::run_cpu_instruction_probe(sha2_probe) == 1) {
            feat |= CPUFeature::Bit::SHA2 & allowed;
         }
         if(OS::run_cpu_instruction_probe(sha512_probe) == 1) {
            feat |= CPUFeature::Bit::SHA2_512 & allowed;
         }
      }
   }

   return feat;
#else
   BOTAN_UNUSED(allowed);
   return {};
#endif
}

}  // namespace

uint32_t CPUID::CPUID_Data::detect_cpu_features(uint32_t allowed) {
   if(auto feat_aux = aarch64_feat_via_auxval(allowed)) {
      return feat_aux.value();
   } else if(auto feat_mac = aarch64_feat_using_mac_api(allowed)) {
      return feat_mac.value();
   } else if(auto feat_instr = aarch64_feat_using_instr_probe(allowed)) {
      return feat_instr.value();
   } else {
      return 0;
   }
}

}  // namespace Botan
/**
* (C) 2025 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

std::string CPUFeature::to_string() const {
   switch(m_bit) {
      case CPUFeature::Bit::NEON:
         return "neon";
      case CPUFeature::Bit::SVE:
         return "sve";
      case CPUFeature::Bit::SHA1:
         return "armv8sha1";
      case CPUFeature::Bit::SHA2:
         return "armv8sha2";
      case CPUFeature::Bit::AES:
         return "armv8aes";
      case CPUFeature::Bit::PMULL:
         return "armv8pmull";
      case CPUFeature::Bit::SHA3:
         return "armv8sha3";
      case CPUFeature::Bit::SHA2_512:
         return "armv8sha2_512";
      case CPUFeature::Bit::SM3:
         return "armv8sm3";
      case CPUFeature::Bit::SM4:
         return "armv8sm4";
   }
   throw Invalid_State("CPUFeature invalid bit");
}

//static
std::optional<CPUFeature> CPUFeature::from_string(std::string_view tok) {
   // TODO(Botan4) remove the "arm_xxx" strings here
   if(tok == "neon" || tok == "simd") {
      return CPUFeature::Bit::NEON;
   } else if(tok == "sve" || tok == "arm_sve") {
      return CPUFeature::Bit::SVE;
   } else if(tok == "armv8sha1" || tok == "arm_sha1") {
      return CPUFeature::Bit::SHA1;
   } else if(tok == "armv8sha2" || tok == "arm_sha2") {
      return CPUFeature::Bit::SHA2;
   } else if(tok == "armv8aes" || tok == "arm_aes") {
      return CPUFeature::Bit::AES;
   } else if(tok == "armv8pmull" || tok == "arm_pmull") {
      return CPUFeature::Bit::PMULL;
   } else if(tok == "armv8sha3" || tok == "arm_sha3") {
      return CPUFeature::Bit::SHA3;
   } else if(tok == "armv8sha2_512" || tok == "arm_sha2_512") {
      return CPUFeature::Bit::SHA2_512;
   } else if(tok == "armv8sm3" || tok == "arm_sm3") {
      return CPUFeature::Bit::SM3;
   } else if(tok == "armv8sm4" || tok == "arm_sm4") {
      return CPUFeature::Bit::SM4;
   } else {
      return {};
   }
}

}  // namespace Botan
/*
* Counter mode
* (C) 1999-2011,2014 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CTR_BE_AVX2) || defined(BOTAN_HAS_CTR_BE_SIMD32)
#endif

namespace Botan {

CTR_BE::CTR_BE(std::unique_ptr<BlockCipher> cipher) :
      m_cipher(std::move(cipher)),
      m_block_size(m_cipher->block_size()),
      m_ctr_size(m_block_size),
      m_ctr_blocks(m_cipher->parallel_bytes() / m_block_size),
      m_counter(m_cipher->parallel_bytes()),
      m_pad(m_counter.size()),
      m_pad_pos(0) {}

CTR_BE::CTR_BE(std::unique_ptr<BlockCipher> cipher, size_t ctr_size) :
      m_cipher(std::move(cipher)),
      m_block_size(m_cipher->block_size()),
      m_ctr_size(ctr_size),
      m_ctr_blocks(m_cipher->parallel_bytes() / m_block_size),
      m_counter(m_cipher->parallel_bytes()),
      m_pad(m_counter.size()),
      m_pad_pos(0) {
   BOTAN_ARG_CHECK(m_ctr_size >= 4 && m_ctr_size <= m_block_size, "Invalid CTR-BE counter size");
}

void CTR_BE::clear() {
   m_cipher->clear();
   zeroise(m_pad);
   zeroise(m_counter);
   zap(m_iv);
   m_pad_pos = 0;
   m_bytes_remaining = 0;
}

std::optional<uint64_t> CTR_BE::remaining_keystream_bytes() const {
   if(!has_keying_material() || m_ctr_size >= sizeof(uint64_t)) {
      return std::nullopt;
   }
   return m_bytes_remaining;
}

size_t CTR_BE::default_iv_length() const {
   return m_block_size;
}

bool CTR_BE::valid_iv_length(size_t iv_len) const {
   return (iv_len <= m_block_size);
}

size_t CTR_BE::buffer_size() const {
   return m_pad.size();
}

Key_Length_Specification CTR_BE::key_spec() const {
   return m_cipher->key_spec();
}

std::unique_ptr<StreamCipher> CTR_BE::new_object() const {
   return std::make_unique<CTR_BE>(m_cipher->new_object(), m_ctr_size);
}

bool CTR_BE::has_keying_material() const {
   return m_cipher->has_keying_material();
}

void CTR_BE::key_schedule(std::span<const uint8_t> key) {
   m_cipher->set_key(key);

   // Set a default all-zeros IV
   set_iv(nullptr, 0);
}

std::string CTR_BE::name() const {
   if(m_ctr_size == m_block_size) {
      return fmt("CTR-BE({})", m_cipher->name());
   } else {
      return fmt("CTR-BE({},{})", m_cipher->name(), m_ctr_size);
   }
}

void CTR_BE::cipher_bytes(const uint8_t in[], uint8_t out[], size_t length) {
   assert_key_material_set();

   if(m_ctr_size < sizeof(uint64_t)) {
      if(length > m_bytes_remaining) {
         throw Invalid_State(fmt("CTR_BE with {}-byte counter has exhausted its keystream", m_ctr_size));
      }
      m_bytes_remaining -= length;
   }

   const uint8_t* pad_bits = m_pad.data();
   const size_t pad_size = m_pad.size();

   /* Consume any already computed keystream in m_pad */

   if(m_pad_pos > 0) {
      const size_t avail = pad_size - m_pad_pos;
      const size_t take = std::min(length, avail);
      xor_buf(out, in, pad_bits + m_pad_pos, take);
      length -= take;
      in += take;
      out += take;
      m_pad_pos += take;

      if(take == avail) {
         add_counter(m_ctr_blocks);
         m_cipher->encrypt_n(m_counter.data(), m_pad.data(), m_ctr_blocks);
         m_pad_pos = 0;
      }
   }

   /* Bulk processing */

   [[maybe_unused]] const bool can_use_bs16_ctr4_fastpath = m_block_size == 16 && m_ctr_size == 4 && pad_size % 64 == 0;

#if defined(BOTAN_HAS_CTR_BE_AVX2)
   if(length >= pad_size && can_use_bs16_ctr4_fastpath && CPUID::has(CPUID::Feature::AVX2)) {
      const size_t consumed = ctr_proc_bs16_ctr4_avx2(in, out, length);
      in += consumed;
      out += consumed;
      length -= consumed;
   }
#endif

#if defined(BOTAN_HAS_CTR_BE_SIMD32)
   if(length >= pad_size && can_use_bs16_ctr4_fastpath && CPUID::has(CPUID::Feature::SIMD_4X32)) {
      const size_t consumed = ctr_proc_bs16_ctr4_simd32(in, out, length);
      in += consumed;
      out += consumed;
      length -= consumed;
   }
#endif

   while(length >= pad_size) {
      xor_buf(out, in, pad_bits, pad_size);
      length -= pad_size;
      in += pad_size;
      out += pad_size;

      add_counter(m_ctr_blocks);
      m_cipher->encrypt_n(m_counter.data(), m_pad.data(), m_ctr_blocks);
   }

   /* Now if length > 0 then we have some remaining text, and m_pad is full - consume as required */
   if(length > 0) {
      xor_buf(out, in, pad_bits, length);
      m_pad_pos = length;
   }
}

void CTR_BE::generate_keystream(uint8_t out[], size_t length) {
   assert_key_material_set();

   if(m_ctr_size < sizeof(uint64_t)) {
      if(length > m_bytes_remaining) {
         throw Invalid_State(fmt("CTR_BE with {}-byte counter has exhausted its keystream", m_ctr_size));
      }
      m_bytes_remaining -= length;
   }

   const size_t avail = m_pad.size() - m_pad_pos;
   const size_t take = std::min(length, avail);
   copy_mem(out, &m_pad[m_pad_pos], take);
   length -= take;
   out += take;
   m_pad_pos += take;

   while(length >= m_pad.size()) {
      add_counter(m_ctr_blocks);
      m_cipher->encrypt_n(m_counter.data(), out, m_ctr_blocks);

      length -= m_pad.size();
      out += m_pad.size();
   }

   if(m_pad_pos == m_pad.size()) {
      add_counter(m_ctr_blocks);
      m_cipher->encrypt_n(m_counter.data(), m_pad.data(), m_ctr_blocks);
      m_pad_pos = 0;
   }

   copy_mem(out, m_pad.data(), length);
   m_pad_pos += length;
   BOTAN_ASSERT_NOMSG(m_pad_pos < m_pad.size());
}

void CTR_BE::set_iv_bytes(const uint8_t iv[], size_t iv_len) {
   if(!valid_iv_length(iv_len)) {
      throw Invalid_IV_Length(name(), iv_len);
   }

   m_iv.resize(m_block_size);
   zeroise(m_iv);
   copy_mem(m_iv.data(), iv, iv_len);

   seek(0);
}

void CTR_BE::add_counter(const uint64_t counter) {
   const size_t ctr_size = m_ctr_size;
   const size_t ctr_blocks = m_ctr_blocks;
   const size_t BS = m_block_size;

   if(ctr_size == 4) {
      const size_t off = (BS - 4);
      const uint32_t low32 = static_cast<uint32_t>(counter + load_be<uint32_t>(&m_counter[off], 0));

      for(size_t i = 0; i != ctr_blocks; ++i) {
         store_be(uint32_t(low32 + i), &m_counter[i * BS + off]);
      }
   } else if(ctr_size == 8) {
      const size_t off = (BS - 8);
      const uint64_t low64 = counter + load_be<uint64_t>(&m_counter[off], 0);

      for(size_t i = 0; i != ctr_blocks; ++i) {
         store_be(uint64_t(low64 + i), &m_counter[i * BS + off]);
      }
   } else if(ctr_size == 16) {
      const size_t off = (BS - 16);
      uint64_t b0 = load_be<uint64_t>(&m_counter[off], 0);
      uint64_t b1 = load_be<uint64_t>(&m_counter[off], 1);
      b1 += counter;
      b0 += (b1 < counter) ? 1 : 0;  // carry

      for(size_t i = 0; i != ctr_blocks; ++i) {
         store_be(b0, &m_counter[i * BS + off]);
         store_be(b1, &m_counter[i * BS + off + 8]);
         b1 += 1;
         if(b1 == 0) {
            b0 += 1;  // carry
         }
      }
   } else {
      for(size_t i = 0; i != ctr_blocks; ++i) {
         uint64_t local_counter = counter;
         uint16_t carry = static_cast<uint8_t>(local_counter);
         for(size_t j = 0; (carry > 0 || local_counter > 0) && j != ctr_size; ++j) {
            const size_t off = i * BS + (BS - 1 - j);
            const uint16_t cnt = static_cast<uint16_t>(m_counter[off]) + carry;
            m_counter[off] = static_cast<uint8_t>(cnt);
            local_counter = (local_counter >> 8);
            carry = (cnt >> 8) + static_cast<uint8_t>(local_counter);
         }
      }
   }
}

void CTR_BE::seek(uint64_t offset) {
   assert_key_material_set();

   if(m_ctr_size < sizeof(uint64_t)) {
      const uint64_t requested_block = offset / m_block_size;
      const uint64_t max_blocks = uint64_t{1} << (8 * m_ctr_size);
      if(requested_block >= max_blocks) {
         throw Invalid_Argument(fmt("CTR_BE::seek offset {} exceeds {}-byte counter range", offset, m_ctr_size));
      }

      m_bytes_remaining = max_blocks * m_block_size - offset;
   }

   const uint64_t base_counter = m_ctr_blocks * (offset / m_counter.size());

   zeroise(m_counter);
   BOTAN_ASSERT_NOMSG(m_counter.size() >= m_iv.size());
   copy_mem(m_counter.data(), m_iv.data(), m_iv.size());

   const size_t BS = m_block_size;

   // Set m_counter blocks to IV, IV + 1, ... IV + n

   if(m_ctr_size == 4 && BS >= 8) {
      const uint32_t low32 = load_be<uint32_t>(&m_counter[BS - 4], 0);

      if(m_ctr_blocks >= 4 && is_power_of_2(m_ctr_blocks)) {
         size_t written = 1;
         while(written < m_ctr_blocks) {
            copy_mem(&m_counter[written * BS], &m_counter[0], BS * written);  // NOLINT(*container-data-pointer)
            written *= 2;
         }
      } else {
         for(size_t i = 1; i != m_ctr_blocks; ++i) {
            copy_mem(&m_counter[i * BS], &m_counter[0], BS - 4);  // NOLINT(*container-data-pointer)
         }
      }

      for(size_t i = 1; i != m_ctr_blocks; ++i) {
         const uint32_t c = static_cast<uint32_t>(low32 + i);
         store_be(c, &m_counter[(BS - 4) + i * BS]);
      }
   } else {
      // do everything sequentially:
      for(size_t i = 1; i != m_ctr_blocks; ++i) {
         copy_mem(&m_counter[i * BS], &m_counter[(i - 1) * BS], BS);

         for(size_t j = 0; j != m_ctr_size; ++j) {
            uint8_t& c = m_counter[i * BS + (BS - 1 - j)];
            c += 1;
            if(c > 0) {
               break;
            }
         }
      }
   }

   if(base_counter > 0) {
      add_counter(base_counter);
   }

   m_cipher->encrypt_n(m_counter.data(), m_pad.data(), m_ctr_blocks);
   m_pad_pos = offset % m_counter.size();
}
}  // namespace Botan
/*
* GCM Mode Encryption
* (C) 2013,2015 Jack Lloyd
* (C) 2016 Daniel Neus, Rohde & Schwarz Cybersecurity
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

/*
* GCM_Mode Constructor
*/
GCM_Mode::GCM_Mode(std::unique_ptr<BlockCipher> cipher, size_t tag_size) :
      m_tag_size(tag_size), m_cipher_name(cipher->name()) {
   if(cipher->block_size() != GCM_BS) {
      throw Invalid_Argument("Invalid block cipher for GCM");
   }

   /* We allow any of the values 128, 120, 112, 104, or 96 bits as a tag size */
   /* 64 bit tag is still supported but deprecated and will be removed in the future */
   if(m_tag_size != 8 && (m_tag_size < 12 || m_tag_size > 16)) {
      throw Invalid_Argument(fmt("{} cannot use a tag of {} bytes", name(), m_tag_size));
   }

   m_ctr = std::make_unique<CTR_BE>(std::move(cipher), 4);
   m_ghash = std::make_unique<GHASH>();
}

GCM_Mode::~GCM_Mode() = default;

void GCM_Mode::clear() {
   m_ctr->clear();
   m_ghash->clear();
   reset();
}

void GCM_Mode::reset() {
   m_ghash->reset_state();
   m_in_msg = false;
}

std::string GCM_Mode::name() const {
   return fmt("{}/GCM({})", m_cipher_name, tag_size());
}

std::string GCM_Mode::provider() const {
   return m_ghash->provider();
}

size_t GCM_Mode::update_granularity() const {
   return 1;
}

size_t GCM_Mode::ideal_granularity() const {
   return GCM_BS * std::max<size_t>(2, BlockCipher::ParallelismMult);
}

bool GCM_Mode::valid_nonce_length(size_t len) const {
   // GCM does not support empty nonces
   return (len > 0);
}

Key_Length_Specification GCM_Mode::key_spec() const {
   return m_ctr->key_spec();
}

bool GCM_Mode::has_keying_material() const {
   return m_ctr->has_keying_material();
}

void GCM_Mode::key_schedule(std::span<const uint8_t> key) {
   reset();
   m_ctr->set_key(key);

   std::array<uint8_t, GCM_BS> zeros{};
   m_ctr->set_iv(zeros);

   uint8_t H[GCM_BS] = {0};
   m_ctr->encipher(H);
   m_ghash->set_key(H);
}

void GCM_Mode::set_associated_data_n(size_t idx, std::span<const uint8_t> ad) {
   BOTAN_ARG_CHECK(idx == 0, "GCM: cannot handle non-zero index in set_associated_data_n");
   m_ghash->set_associated_data(ad);
}

void GCM_Mode::start_msg(const uint8_t nonce[], size_t nonce_len) {
   BOTAN_STATE_CHECK(!m_in_msg);

   if(!valid_nonce_length(nonce_len)) {
      throw Invalid_IV_Length(name(), nonce_len);
   }

   std::array<uint8_t, GCM_BS> y0 = {};

   if(nonce_len == 12) {
      copy_mem(y0.data(), nonce, nonce_len);
      y0[15] = 1;
   } else {
      m_ghash->nonce_hash(std::span<uint8_t, GCM_BS>(y0), {nonce, nonce_len});
   }

   m_ctr->set_iv(y0.data(), y0.size());

   clear_mem(y0.data(), y0.size());
   m_ctr->encipher(y0);

   m_ghash->start(y0);
   secure_scrub_memory(y0);
   m_in_msg = true;
}

size_t GCM_Encryption::output_length(size_t input_length) const {
   return add_or_throw(input_length, tag_size(), "GCM input too large");
}

size_t GCM_Encryption::process_msg(uint8_t buf[], size_t sz) {
   BOTAN_STATE_CHECK(m_in_msg);
   BOTAN_ARG_CHECK(sz % update_granularity() == 0, "Invalid buffer size");
   m_ctr->cipher(buf, buf, sz);
   m_ghash->update({buf, sz});
   return sz;
}

void GCM_Encryption::finish_msg(secure_vector<uint8_t>& buffer, size_t offset) {
   BOTAN_STATE_CHECK(m_in_msg);
   BOTAN_ARG_CHECK(offset <= buffer.size(), "Invalid offset");
   const size_t sz = buffer.size() - offset;
   uint8_t* buf = buffer.data() + offset;

   m_ctr->cipher(buf, buf, sz);
   m_ghash->update({buf, sz});

   std::array<uint8_t, 16> mac = {0};
   m_ghash->final(std::span(mac).first(tag_size()));
   buffer += std::make_pair(mac.data(), tag_size());
   m_in_msg = false;
}

size_t GCM_Decryption::output_length(size_t input_length) const {
   BOTAN_ARG_CHECK(input_length >= tag_size(), "Message too short to be valid");
   return input_length - tag_size();
}

size_t GCM_Decryption::process_msg(uint8_t buf[], size_t sz) {
   BOTAN_STATE_CHECK(m_in_msg);
   BOTAN_ARG_CHECK(sz % update_granularity() == 0, "Invalid buffer size");
   m_ghash->update({buf, sz});
   m_ctr->cipher(buf, buf, sz);
   return sz;
}

void GCM_Decryption::finish_msg(secure_vector<uint8_t>& buffer, size_t offset) {
   BOTAN_STATE_CHECK(m_in_msg);
   BOTAN_ARG_CHECK(offset <= buffer.size(), "Invalid offset");
   const size_t sz = buffer.size() - offset;
   uint8_t* buf = buffer.data() + offset;

   BOTAN_ARG_CHECK(sz >= tag_size(), "input did not include the tag");

   const size_t remaining = sz - tag_size();

   // handle any final input before the tag
   if(remaining > 0) {
      m_ghash->update({buf, remaining});
      m_ctr->cipher(buf, buf, remaining);
   }

   std::array<uint8_t, 16> mac = {0};
   m_ghash->final(std::span(mac).first(tag_size()));

   const uint8_t* included_tag = &buffer[remaining + offset];

   m_in_msg = false;

   if(!CT::is_equal(mac.data(), included_tag, tag_size()).as_bool()) {
      clear_mem(std::span{buffer}.subspan(offset, remaining));
      throw Invalid_Authentication_Tag("GCM tag check failed");
   }

   buffer.resize(offset + remaining);
}

}  // namespace Botan
/*
* GCM GHASH
* (C) 2013,2015,2017 Jack Lloyd
* (C) 2016 Daniel Neus, Rohde & Schwarz Cybersecurity
* (C) 2024 René Meusel, Rohde & Schwarz Cybersecurity
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

namespace Botan {

std::string GHASH::provider() const {
#if defined(BOTAN_HAS_GHASH_AVX512_CLMUL)
   if(auto feat = CPUID::check(CPUID::Feature::AVX512_CLMUL)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_CPU)
   if(auto feat = CPUID::check(CPUID::Feature::HW_CLMUL)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_VPERM)
   if(auto feat = CPUID::check(CPUID::Feature::SIMD_4X32)) {
      return *feat;
   }
#endif

   return "base";
}

void GHASH::ghash_multiply(std::span<uint8_t, GCM_BS> x, std::span<const uint8_t> input, size_t blocks) {
   BOTAN_ASSERT_NOMSG(input.size() % GCM_BS == 0);

#if defined(BOTAN_HAS_GHASH_AVX512_CLMUL)
   if(CPUID::has(CPUID::Feature::AVX512_CLMUL)) {
      BOTAN_ASSERT_NOMSG(!m_H_pow.empty());
      return ghash_multiply_avx512_clmul(x.data(), m_H_pow.data(), input.data(), blocks);
   }
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_CPU)
   if(CPUID::has(CPUID::Feature::HW_CLMUL)) {
      BOTAN_ASSERT_NOMSG(!m_H_pow.empty());
      return ghash_multiply_cpu(x.data(), m_H_pow, input.data(), blocks);
   }
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_VPERM)
   if(CPUID::has(CPUID::Feature::SIMD_2X64)) {
      return ghash_multiply_vperm(x.data(), m_HM.data(), input.data(), blocks);
   }
#endif

   ghash_multiply_base(x, m_HM, input, blocks);
}

void GHASH::ghash_multiply_base(std::span<uint8_t, GCM_BS> x,
                                const secure_vector<uint64_t>& HM,
                                std::span<const uint8_t> input,
                                size_t blocks) {
   auto scope = CT::scoped_poison(x);

   auto X = load_be<std::array<uint64_t, 2>>(x);

   BufferSlicer in(input);
   for(size_t b = 0; b != blocks; ++b) {
      const auto I = load_be<std::array<uint64_t, 2>>(in.take<GCM_BS>());
      X[0] ^= I[0];
      X[1] ^= I[1];

      std::array<uint64_t, 2> Z{};

      for(size_t i = 0; i != 64; ++i) {
         const auto X0MASK = CT::Mask<uint64_t>::expand_top_bit(X[0]);
         const auto X1MASK = CT::Mask<uint64_t>::expand_top_bit(X[1]);

         X[0] <<= 1;
         X[1] <<= 1;

         Z[0] = X0MASK.select(Z[0] ^ HM[4 * i], Z[0]);
         Z[1] = X0MASK.select(Z[1] ^ HM[4 * i + 1], Z[1]);

         Z[0] = X1MASK.select(Z[0] ^ HM[4 * i + 2], Z[0]);
         Z[1] = X1MASK.select(Z[1] ^ HM[4 * i + 3], Z[1]);
      }

      X[0] = Z[0];
      X[1] = Z[1];
   }

   store_be(x, X);
}

bool GHASH::has_keying_material() const {
   return !m_HM.empty() || !m_H_pow.empty();
}

void GHASH::key_schedule(std::span<const uint8_t> key) {
   m_H_ad = {0};
   m_ad_len = 0;
   m_text_len = 0;

   BOTAN_ASSERT_NOMSG(key.size() == GCM_BS);

#if defined(BOTAN_HAS_GHASH_AVX512_CLMUL)
   if(CPUID::has(CPUID::Feature::AVX512_CLMUL)) {
      zap(m_HM);
      if(m_H_pow.size() != 32) {
         m_H_pow.resize(32);
      }
      ghash_precompute_avx512_clmul(key.data(), m_H_pow.data());
      // m_HM left empty
      return;
   }
#endif

#if defined(BOTAN_HAS_GHASH_CLMUL_CPU)
   if(CPUID::has(CPUID::Feature::HW_CLMUL)) {
      zap(m_HM);
      ghash_precompute_cpu(key.data(), m_H_pow);
      // m_HM left empty
      return;
   }
#endif

   ghash_precompute_base(key.first<GCM_BS>(), m_HM);
}

void GHASH::ghash_precompute_base(std::span<const uint8_t, GCM_BS> key, secure_vector<uint64_t>& HM) {
   auto H = load_be<std::array<uint64_t, 2>>(key);

   const uint64_t R = 0xE100000000000000;

   if(HM.size() != 256) {
      HM.resize(256);
   }

   // precompute the multiples of H
   for(size_t i = 0; i != 2; ++i) {
      for(size_t j = 0; j != 64; ++j) {
         /*
         we interleave H^1, H^65, H^2, H^66, H3, H67, H4, H68
         to make indexing nicer in the multiplication code
         */
         HM[4 * j + 2 * i] = H[0];
         HM[4 * j + 2 * i + 1] = H[1];

         // GCM's bit ops are reversed so we carry out of the bottom
         const uint64_t carry = CT::Mask<uint64_t>::expand(H[1] & 1).if_set_return(R);
         H[1] = (H[1] >> 1) | (H[0] << 63);
         H[0] = (H[0] >> 1) ^ carry;
      }
   }
}

void GHASH::start(std::span<const uint8_t> nonce) {
   BOTAN_ARG_CHECK(nonce.size() == 16, "GHASH requires a 128-bit nonce");
   auto& n = m_nonce.emplace();
   copy_mem(n, nonce);
   copy_mem(m_ghash, m_H_ad);
   m_buffer.clear();
   m_text_len = 0;
}

void GHASH::set_associated_data(std::span<const uint8_t> input) {
   BOTAN_STATE_CHECK(!m_nonce);

   assert_key_material_set();
   m_H_ad = {0};
   ghash_update(m_H_ad, input);
   ghash_zeropad(m_H_ad);
   m_ad_len = input.size();
}

void GHASH::reset_associated_data() {
   // This should only be called in GMAC context
   BOTAN_STATE_CHECK(m_text_len == 0);
   assert_key_material_set();
   m_H_ad = {0};
   m_ad_len = 0;
}

void GHASH::update_associated_data(std::span<const uint8_t> ad) {
   assert_key_material_set();
   ghash_update(m_ghash, ad);
   m_ad_len += ad.size();
}

void GHASH::update(std::span<const uint8_t> input) {
   assert_key_material_set();
   BOTAN_STATE_CHECK(m_nonce);
   ghash_update(m_ghash, input);
   m_text_len += input.size();

   // NIST SP 800-38D limits plaintext/ciphertext to 2^39 - 256 bits
   constexpr uint64_t GHASH_MAX_BYTES = (((static_cast<uint64_t>(1) << 39)) - 256) / 8;
   if(m_text_len > GHASH_MAX_BYTES) {
      throw Invalid_State("GCM message length limit exceeded");
   }
}

void GHASH::final(std::span<uint8_t> mac) {
   BOTAN_ARG_CHECK(!mac.empty() && mac.size() <= GCM_BS, "GHASH output length");
   BOTAN_STATE_CHECK(m_nonce);
   assert_key_material_set();

   ghash_zeropad(m_ghash);
   ghash_final_block(m_ghash, m_ad_len, m_text_len);

   xor_buf(mac, std::span{m_ghash}.first(mac.size()), std::span{*m_nonce}.first(mac.size()));

   secure_scrub_memory(m_ghash);
   m_text_len = 0;
   m_nonce.reset();
}

void GHASH::nonce_hash(std::span<uint8_t, GCM_BS> y0, std::span<const uint8_t> nonce) {
   assert_key_material_set();
   BOTAN_STATE_CHECK(!m_nonce);

   ghash_update(y0, nonce);
   ghash_zeropad(y0);
   ghash_final_block(y0, 0, nonce.size());
}

void GHASH::clear() {
   zap(m_HM);
   zap(m_H_pow);
   m_H_ad = {0};
   m_ad_len = 0;
   this->reset_state();
}

void GHASH::reset_state() {
   secure_scrub_memory(m_ghash);
   if(m_nonce) {
      secure_scrub_memory(m_nonce.value());
      m_nonce.reset();
   }
   m_buffer.clear();
   m_text_len = 0;
}

void GHASH::ghash_update(std::span<uint8_t, GCM_BS> x, std::span<const uint8_t> input) {
   BufferSlicer in(input);
   while(!in.empty()) {
      if(const auto one_block = m_buffer.handle_unaligned_data(in)) {
         ghash_multiply(x, one_block.value(), 1);
      }

      if(m_buffer.in_alignment()) {
         const auto [aligned_data, full_blocks] = m_buffer.aligned_data_to_process(in);
         if(full_blocks > 0) {
            ghash_multiply(x, aligned_data, full_blocks);
         }
      }
   }
   BOTAN_ASSERT_NOMSG(in.empty());
}

void GHASH::ghash_zeropad(std::span<uint8_t, GCM_BS> x) {
   if(!m_buffer.in_alignment()) {
      m_buffer.fill_up_with_zeros();
      ghash_multiply(x, m_buffer.consume(), 1);
   }
}

void GHASH::ghash_final_block(std::span<uint8_t, GCM_BS> x, uint64_t ad_len, uint64_t text_len) {
   BOTAN_STATE_CHECK(m_buffer.in_alignment());
   const auto final_block = store_be(8 * ad_len, 8 * text_len);
   ghash_multiply(x, final_block, 1);
}

}  // namespace Botan
/*
* Hash Functions
* (C) 2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_ADLER32)
#endif

#if defined(BOTAN_HAS_ASCON_HASH256)
#endif

#if defined(BOTAN_HAS_CRC24)
#endif

#if defined(BOTAN_HAS_CRC32)
#endif

#if defined(BOTAN_HAS_GOST_34_11)
#endif

#if defined(BOTAN_HAS_KECCAK)
#endif

#if defined(BOTAN_HAS_MD4)
#endif

#if defined(BOTAN_HAS_MD5)
#endif

#if defined(BOTAN_HAS_RIPEMD_160)
#endif

#if defined(BOTAN_HAS_SHA1)
#endif

#if defined(BOTAN_HAS_SHA2_32)
#endif

#if defined(BOTAN_HAS_SHA2_64)
#endif

#if defined(BOTAN_HAS_SHA3)
#endif

#if defined(BOTAN_HAS_SHAKE)
#endif

#if defined(BOTAN_HAS_SKEIN_512)
#endif

#if defined(BOTAN_HAS_STREEBOG)
#endif

#if defined(BOTAN_HAS_SM3)
#endif

#if defined(BOTAN_HAS_WHIRLPOOL)
#endif

#if defined(BOTAN_HAS_PARALLEL_HASH)
#endif

#if defined(BOTAN_HAS_TRUNCATED_HASH)
#endif

#if defined(BOTAN_HAS_COMB4P)
#endif

#if defined(BOTAN_HAS_BLAKE2B)
#endif

#if defined(BOTAN_HAS_BLAKE2S)
#endif

#if defined(BOTAN_HAS_COMMONCRYPTO)
#endif

namespace Botan {

std::unique_ptr<HashFunction> HashFunction::create(std::string_view algo_spec, std::string_view provider) {
#if defined(BOTAN_HAS_COMMONCRYPTO)
   if(provider.empty() || provider == "commoncrypto") {
      if(auto hash = make_commoncrypto_hash(algo_spec))
         return hash;

      if(!provider.empty())
         return nullptr;
   }
#endif

   if(provider.empty() == false && provider != "base") {
      return nullptr;  // unknown provider
   }

#if defined(BOTAN_HAS_SHA1)
   if(algo_spec == "SHA-1") {
      return std::make_unique<SHA_1>();
   }
#endif

#if defined(BOTAN_HAS_SHA2_32)
   if(algo_spec == "SHA-224") {
      return std::make_unique<SHA_224>();
   }

   if(algo_spec == "SHA-256") {
      return std::make_unique<SHA_256>();
   }
#endif

#if defined(BOTAN_HAS_SHA2_64)
   if(algo_spec == "SHA-384") {
      return std::make_unique<SHA_384>();
   }

   if(algo_spec == "SHA-512") {
      return std::make_unique<SHA_512>();
   }

   if(algo_spec == "SHA-512-256") {
      return std::make_unique<SHA_512_256>();
   }
#endif

#if defined(BOTAN_HAS_RIPEMD_160)
   if(algo_spec == "RIPEMD-160") {
      return std::make_unique<RIPEMD_160>();
   }
#endif

#if defined(BOTAN_HAS_WHIRLPOOL)
   if(algo_spec == "Whirlpool") {
      return std::make_unique<Whirlpool>();
   }
#endif

#if defined(BOTAN_HAS_MD5)
   if(algo_spec == "MD5") {
      return std::make_unique<MD5>();
   }
#endif

#if defined(BOTAN_HAS_MD4)
   if(algo_spec == "MD4") {
      return std::make_unique<MD4>();
   }
#endif

#if defined(BOTAN_HAS_GOST_34_11)
   if(algo_spec == "GOST-R-34.11-94" || algo_spec == "GOST-34.11") {
      return std::make_unique<GOST_34_11>();
   }
#endif

#if defined(BOTAN_HAS_ADLER32)
   if(algo_spec == "Adler32") {
      return std::make_unique<Adler32>();
   }
#endif

#if defined(BOTAN_HAS_ASCON_HASH256)
   if(algo_spec == "Ascon-Hash256") {
      return std::make_unique<Ascon_Hash256>();
   }
#endif

#if defined(BOTAN_HAS_CRC24)
   if(algo_spec == "CRC24") {
      return std::make_unique<CRC24>();
   }
#endif

#if defined(BOTAN_HAS_CRC32)
   if(algo_spec == "CRC32") {
      return std::make_unique<CRC32>();
   }
#endif

#if defined(BOTAN_HAS_STREEBOG)
   if(algo_spec == "Streebog-256") {
      return std::make_unique<Streebog>(256);
   }
   if(algo_spec == "Streebog-512") {
      return std::make_unique<Streebog>(512);
   }
#endif

#if defined(BOTAN_HAS_SM3)
   if(algo_spec == "SM3") {
      return std::make_unique<SM3>();
   }
#endif

   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_SKEIN_512)
   if(req.algo_name() == "Skein-512") {
      return std::make_unique<Skein_512>(req.arg_as_integer(0, 512), req.arg(1, ""));
   }
#endif

#if defined(BOTAN_HAS_BLAKE2B)
   if(req.algo_name() == "Blake2b" || req.algo_name() == "BLAKE2b") {
      return std::make_unique<BLAKE2b>(req.arg_as_integer(0, 512));
   }
#endif

#if defined(BOTAN_HAS_BLAKE2S)
   if(req.algo_name() == "Blake2s" || req.algo_name() == "BLAKE2s") {
      return std::make_unique<BLAKE2s>(req.arg_as_integer(0, 256));
   }
#endif

#if defined(BOTAN_HAS_KECCAK)
   if(req.algo_name() == "Keccak-1600") {
      return std::make_unique<Keccak_1600>(req.arg_as_integer(0, 512));
   }
#endif

#if defined(BOTAN_HAS_SHA3)
   if(req.algo_name() == "SHA-3") {
      return std::make_unique<SHA_3>(req.arg_as_integer(0, 512));
   }
#endif

#if defined(BOTAN_HAS_SHAKE)
   if(req.algo_name() == "SHAKE-128" && req.arg_count() == 1) {
      return std::make_unique<SHAKE_128>(req.arg_as_integer(0));
   }
   if(req.algo_name() == "SHAKE-256" && req.arg_count() == 1) {
      return std::make_unique<SHAKE_256>(req.arg_as_integer(0));
   }
#endif

#if defined(BOTAN_HAS_PARALLEL_HASH)
   if(req.algo_name() == "Parallel") {
      std::vector<std::unique_ptr<HashFunction>> hashes;

      for(size_t i = 0; i != req.arg_count(); ++i) {
         auto h = HashFunction::create(req.arg(i));
         if(!h) {
            return nullptr;
         }
         hashes.push_back(std::move(h));
      }

      return std::make_unique<Parallel>(hashes);
   }
#endif

#if defined(BOTAN_HAS_TRUNCATED_HASH)
   if(req.algo_name() == "Truncated" && req.arg_count() == 2) {
      auto hash = HashFunction::create(req.arg(0));
      if(!hash) {
         return nullptr;
      }

      return std::make_unique<Truncated_Hash>(std::move(hash), req.arg_as_integer(1));
   }
#endif

#if defined(BOTAN_HAS_COMB4P)
   if(req.algo_name() == "Comb4P" && req.arg_count() == 2) {
      auto h1 = HashFunction::create(req.arg(0));
      auto h2 = HashFunction::create(req.arg(1));

      if(h1 && h2) {
         return std::make_unique<Comb4P>(std::move(h1), std::move(h2));
      }
   }
#endif

   return nullptr;
}

//static
std::unique_ptr<HashFunction> HashFunction::create_or_throw(std::string_view algo, std::string_view provider) {
   if(auto hash = HashFunction::create(algo, provider)) {
      return hash;
   }
   throw Lookup_Error("Hash", algo, provider);
}

std::vector<std::string> HashFunction::providers(std::string_view algo_spec) {
   return probe_providers_of<HashFunction>(algo_spec, {"base", "commoncrypto"});
}

}  // namespace Botan
/*
* Hex Encoding and Decoding
* (C) 2010,2020 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

uint16_t hex_encode_2nibble(uint8_t n8, bool uppercase) {
   // Offset for upper or lower case 'a' resp
   const uint16_t a_mask = uppercase ? 0x0707 : 0x2727;

   const uint16_t n = (static_cast<uint16_t>(n8 & 0xF0) << 4) | (n8 & 0x0F);
   // n >= 10? If so add offset
   const uint16_t diff = swar_lt<uint16_t>(0x0909, n) & a_mask;
   // Can't overflow between bytes, so don't need explicit SWAR addition:
   return n + 0x3030 + diff;
}

}  // namespace

void hex_encode(char output[], const uint8_t input[], size_t input_length, bool uppercase) {
   for(size_t i = 0; i != input_length; ++i) {
      const uint16_t h = hex_encode_2nibble(input[i], uppercase);
      output[2 * i] = get_byte<0>(h);
      output[2 * i + 1] = get_byte<1>(h);
   }
}

std::string hex_encode(const uint8_t input[], size_t input_length, bool uppercase) {
   const size_t output_length = mul_or_throw<size_t>(2, input_length, "Input too large to hex encode");
   std::string output(output_length, 0);

   if(input_length > 0) {
      hex_encode(&output.front(), input, input_length, uppercase);
   }

   return output;
}

namespace {

uint8_t hex_char_to_bin(char input) {
   // Starts of valid value ranges (v_lo) and their lengths (v_range)
   constexpr uint64_t v_lo = make_uint64(0, '0', 'a', 'A', ' ', '\n', '\t', '\r');
   constexpr uint64_t v_range = make_uint64(0, 10, 6, 6, 1, 1, 1, 1);
   constexpr uint64_t expand8 = 0x0101010101010101;
   constexpr uint64_t top64 = 0x8000000000000000;

   const uint8_t x = static_cast<uint8_t>(input);
   const uint64_t x8 = x * expand8;

   const uint64_t v_mask = swar_in_range<uint64_t>(x8, v_lo, v_range) ^ top64;

   // This is the offset added to x to get the value we need
   const uint64_t val_v = 0xd0a9c960767773 ^ static_cast<uint64_t>(0xFF - x) << 56;

   return x + static_cast<uint8_t>(val_v >> (8 * index_of_first_set_byte(v_mask)));
}

}  // namespace

size_t hex_decode(uint8_t output[], const char input[], size_t input_length, size_t& input_consumed, bool ignore_ws) {
   uint8_t* out_ptr = output;
   bool top_nibble = true;
   uint8_t next = 0;

   input_consumed = 0;

   clear_mem(output, input_length / 2);

   for(size_t i = 0; i != input_length; ++i) {
      const uint8_t bin = hex_char_to_bin(input[i]);

      if(bin >= 0x10) {
         if(bin == 0x80 && ignore_ws) {
            continue;
         }

         throw Invalid_Argument(fmt("hex_decode: invalid character '{}'", format_char_for_display(input[i])));
      }

      if(top_nibble) {
         next = bin << 4;
      } else {
         next |= bin;
         *out_ptr = next;
      }

      top_nibble = !top_nibble;
      if(top_nibble) {
         ++out_ptr;
         input_consumed = i + 1;
      }
   }

   /*
   * Consume trailing whitespace following the last full byte; a leftover
   * unpaired nibble (if any) stops the scan and is left unconsumed.
   */
   while(input_consumed < input_length && hex_char_to_bin(input[input_consumed]) == 0x80) {
      ++input_consumed;
   }

   return (out_ptr - output);
}

size_t hex_decode(uint8_t output[], const char input[], size_t input_length, bool ignore_ws) {
   size_t consumed = 0;
   const size_t written = hex_decode(output, input, input_length, consumed, ignore_ws);

   if(consumed != input_length) {
      throw Invalid_Argument("hex_decode: input did not have full bytes");
   }

   return written;
}

size_t hex_decode(uint8_t output[], std::string_view input, bool ignore_ws) {
   return hex_decode(output, input.data(), input.length(), ignore_ws);
}

size_t hex_decode(std::span<uint8_t> output, std::string_view input, bool ignore_ws) {
   if(output.size() < input.length() / 2) {
      throw Invalid_Argument("hex_decode: output buffer too small");
   }
   return hex_decode(output.data(), input.data(), input.length(), ignore_ws);
}

secure_vector<uint8_t> hex_decode_locked(const char input[], size_t input_length, bool ignore_ws) {
   secure_vector<uint8_t> bin(1 + input_length / 2);

   const size_t written = hex_decode(bin.data(), input, input_length, ignore_ws);

   bin.resize(written);
   return bin;
}

secure_vector<uint8_t> hex_decode_locked(std::string_view input, bool ignore_ws) {
   return hex_decode_locked(input.data(), input.size(), ignore_ws);
}

std::vector<uint8_t> hex_decode(const char input[], size_t input_length, bool ignore_ws) {
   std::vector<uint8_t> bin(1 + input_length / 2);

   const size_t written = hex_decode(bin.data(), input, input_length, ignore_ws);

   bin.resize(written);
   return bin;
}

std::vector<uint8_t> hex_decode(std::string_view input, bool ignore_ws) {
   return hex_decode(input.data(), input.size(), ignore_ws);
}

}  // namespace Botan
/*
* HKDF
* (C) 2013,2015,2017 Jack Lloyd
* (C) 2016 René Korthaus, Rohde & Schwarz Cybersecurity
* (C) 2024 René Meusel, Rohde & Schwarz Cybersecurity
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

std::unique_ptr<KDF> HKDF::new_object() const {
   return std::make_unique<HKDF>(m_prf->new_object());
}

std::string HKDF::name() const {
   return fmt("HKDF({})", m_prf->name());
}

void HKDF::perform_kdf(std::span<uint8_t> key,
                       std::span<const uint8_t> secret,
                       std::span<const uint8_t> salt,
                       std::span<const uint8_t> label) const {
   const HKDF_Extract extract(m_prf->new_object());
   const HKDF_Expand expand(m_prf->new_object());
   secure_vector<uint8_t> prk(m_prf->output_length());

   extract.derive_key(prk, secret, salt, {});
   expand.derive_key(key, prk, {}, label);
}

std::unique_ptr<KDF> HKDF_Extract::new_object() const {
   return std::make_unique<HKDF_Extract>(m_prf->new_object());
}

std::string HKDF_Extract::name() const {
   return fmt("HKDF-Extract({})", m_prf->name());
}

void HKDF_Extract::perform_kdf(std::span<uint8_t> key,
                               std::span<const uint8_t> secret,
                               std::span<const uint8_t> salt,
                               std::span<const uint8_t> label) const {
   const size_t prf_output_len = m_prf->output_length();
   BOTAN_ARG_CHECK(key.size() <= prf_output_len, "HKDF-Extract maximum output length exceeded");
   BOTAN_ARG_CHECK(label.empty(), "HKDF-Extract does not support a label input");

   if(key.empty()) {
      return;
   }

   if(salt.empty()) {
      m_prf->set_key(std::vector<uint8_t>(prf_output_len));
   } else {
      m_prf->set_key(salt);
   }

   m_prf->update(secret);

   if(key.size() == prf_output_len) {
      m_prf->final(key);
   } else {
      const auto prk = m_prf->final();
      copy_mem(key, std::span{prk}.first(key.size()));
   }
}

std::unique_ptr<KDF> HKDF_Expand::new_object() const {
   return std::make_unique<HKDF_Expand>(m_prf->new_object());
}

std::string HKDF_Expand::name() const {
   return fmt("HKDF-Expand({})", m_prf->name());
}

void HKDF_Expand::perform_kdf(std::span<uint8_t> key,
                              std::span<const uint8_t> secret,
                              std::span<const uint8_t> salt,
                              std::span<const uint8_t> label) const {
   const auto prf_output_length = m_prf->output_length();
   BOTAN_ARG_CHECK(key.size() <= prf_output_length * 255, "HKDF-Expand maximum output length exceeded");

   if(key.empty()) {
      return;
   }

   // Keep a reference to the previous PRF output (empty by default).
   std::span<uint8_t> h = {};

   BufferStuffer k(key);
   m_prf->set_key(secret);
   for(uint8_t counter = 1; !k.full(); ++counter) {
      m_prf->update(h);
      m_prf->update(label);
      m_prf->update(salt);
      m_prf->update(counter);

      // Write straight into the output buffer, except if the PRF output needs
      // a truncation in the final iteration.
      if(k.remaining_capacity() >= prf_output_length) {
         h = k.next(prf_output_length);
         m_prf->final(h);
      } else {
         const auto full_prf_output = m_prf->final();
         h = {};  // this is the final iteration!
         k.append(std::span{full_prf_output}.first(k.remaining_capacity()));
      }
   }
}

secure_vector<uint8_t> hkdf_expand_label(std::string_view hash_fn,
                                         std::span<const uint8_t> secret,
                                         std::string_view label,
                                         std::span<const uint8_t> hash_val,
                                         size_t length) {
   BOTAN_ARG_CHECK(length <= 0xFFFF, "HKDF-Expand-Label requested output too large");
   BOTAN_ARG_CHECK(label.size() <= 0xFF, "HKDF-Expand-Label label too long");
   BOTAN_ARG_CHECK(hash_val.size() <= 0xFF, "HKDF-Expand-Label hash too long");

   const HKDF_Expand hkdf(MessageAuthenticationCode::create_or_throw(fmt("HMAC({})", hash_fn)));

   const auto prefix = concat<std::vector<uint8_t>>(store_be(static_cast<uint16_t>(length)),
                                                    store_be(static_cast<uint8_t>(label.size())),
                                                    as_span_of_bytes(label),
                                                    store_be(static_cast<uint8_t>(hash_val.size())));

   /*
   * We do something a little dirty here to avoid copying the hash_val,
   * making use of the fact that Botan's KDF interface supports label+salt,
   * and knowing that our HKDF hashes first param label then param salt.
   */
   return hkdf.derive_key(length, secret, hash_val, prefix);
}

}  // namespace Botan
/*
* HMAC
* (C) 1999-2007,2014,2020 Jack Lloyd
*     2007 Yves Jerschow
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

/*
* Update a HMAC Calculation
*/
void HMAC::add_data(std::span<const uint8_t> input) {
   assert_key_material_set();
   m_hash->update(input);
}

/*
* Finalize a HMAC Calculation
*/
void HMAC::final_result(std::span<uint8_t> mac) {
   assert_key_material_set();
   m_hash->final(mac);
   m_hash->update(m_okey);
   m_hash->update(mac.first(m_hash_output_length));
   m_hash->final(mac);
   m_hash->update(m_ikey);
}

void HMAC::start_msg(std::span<const uint8_t> nonce) {
   if(!nonce.empty()) {
      throw Invalid_IV_Length(name(), nonce.size());
   }
   assert_key_material_set();

   m_hash->clear();
   m_hash->update(m_ikey);
}

Key_Length_Specification HMAC::key_spec() const {
   // Support very long lengths for things like PBKDF2 and the TLS PRF
   return Key_Length_Specification(0, 8192);
}

size_t HMAC::output_length() const {
   return m_hash_output_length;
}

bool HMAC::has_keying_material() const {
   return !m_okey.empty();
}

/*
* HMAC Key Schedule
*/
void HMAC::key_schedule(std::span<const uint8_t> key) {
   const uint8_t ipad = 0x36;
   const uint8_t opad = 0x5C;

   m_hash->clear();

   m_ikey.resize(m_hash_block_size);
   m_okey.resize(m_hash_block_size);

   clear_mem(m_ikey.data(), m_ikey.size());
   clear_mem(m_okey.data(), m_okey.size());

   /*
   * Sometimes the HMAC key length itself is sensitive, as with PBKDF2 where it
   * reveals the length of the passphrase. Make some attempt to hide this to
   * side channels. Clearly if the secret is longer than the block size then the
   * branch to hash first reveals that. In addition, counting the number of
   * compression functions executed reveals the size at the granularity of the
   * hash function's block size.
   *
   * The greater concern is for smaller keys; being able to detect when a
   * passphrase is say 4 bytes may assist choosing weaker targets. Even though
   * the loop bounds are constant, we can only actually read key[0..length] so
   * it doesn't seem possible to make this computation truly constant time.
   *
   * We don't mind leaking if the length is exactly zero since that's
   * trivial to simply check.
   */

   if(key.size() > m_hash_block_size) {
      m_hash->update(key);
      m_hash->final(m_ikey.data());
   } else if(key.size() >= 20) {
      // For long keys we just leak the length either it is a cryptovariable
      // or a long enough password that just the length is not a useful signal
      copy_mem(std::span{m_ikey}.first(key.size()), key);
   } else if(!key.empty()) {
      for(size_t i = 0, i_mod_length = 0; i != m_hash_block_size; ++i) {
         /*
         access key[i % length] but avoiding division due to variable
         time computation on some processors.
         */
         auto needs_reduction = CT::Mask<size_t>::is_lte(key.size(), i_mod_length);
         i_mod_length = needs_reduction.select(0, i_mod_length);
         const uint8_t kb = key[i_mod_length];

         auto in_range = CT::Mask<size_t>::is_lt(i, key.size());
         m_ikey[i] = static_cast<uint8_t>(in_range.if_set_return(kb));
         i_mod_length += 1;
      }
   }

   for(size_t i = 0; i != m_hash_block_size; ++i) {
      m_ikey[i] ^= ipad;
      m_okey[i] = m_ikey[i] ^ ipad ^ opad;
   }

   m_hash->update(m_ikey);
}

/*
* Clear memory of sensitive data
*/
void HMAC::clear() {
   m_hash->clear();
   zap(m_ikey);
   zap(m_okey);
}

/*
* Return the name of this type
*/
std::string HMAC::name() const {
   return fmt("HMAC({})", m_hash->name());
}

/*
* Return a new_object of this object
*/
std::unique_ptr<MessageAuthenticationCode> HMAC::new_object() const {
   return std::make_unique<HMAC>(m_hash->new_object());
}

/*
* HMAC Constructor
*/
HMAC::HMAC(std::unique_ptr<HashFunction> hash) :
      m_hash(std::move(hash)),
      m_hash_output_length(m_hash->output_length()),
      m_hash_block_size(m_hash->hash_block_size()) {
   BOTAN_ARG_CHECK(m_hash_output_length >= 8, "HMAC is not compatible with this hash function");
   BOTAN_ARG_CHECK(m_hash_block_size >= m_hash_output_length, "HMAC is not compatible with this hash function");
}

}  // namespace Botan
/*
* HMAC_DRBG
* (C) 2014,2015,2016 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

size_t hmac_drbg_security_level(size_t mac_output_length) {
   // security strength of the hash function
   // for pre-image resistance (see NIST SP 800-57)
   // SHA-1: 128 bits
   // SHA-224, SHA-512/224: 192 bits,
   // SHA-256, SHA-512/256, SHA-384, SHA-512: >= 256 bits
   // NIST SP 800-90A only supports up to 256 bits though

   if(mac_output_length < 20) {
      throw Invalid_Argument(fmt("HMAC_DRBG MAC output length {} is too small", mac_output_length));
   }

   if(mac_output_length < 32) {
      return (mac_output_length - 4) * 8;
   } else {
      return 32 * 8;
   }
}

void check_limits(size_t reseed_interval, size_t max_number_of_bytes_per_request) {
   // SP800-90A permits up to 2^48, but it is not usable on 32 bit
   // platforms, so we only allow up to 2^24, which is still reasonably high
   if(reseed_interval == 0 || reseed_interval > static_cast<size_t>(1) << 24) {
      throw Invalid_Argument("Invalid value for reseed_interval");
   }

   if(max_number_of_bytes_per_request == 0 || max_number_of_bytes_per_request > 64 * 1024) {
      throw Invalid_Argument("Invalid value for max_number_of_bytes_per_request");
   }
}

template <typename T>
std::unique_ptr<T> check_not_null(std::unique_ptr<T> obj) {
   BOTAN_ARG_CHECK(obj != nullptr, "Argument must not be null");
   return obj;
}

}  // namespace

HMAC_DRBG::~HMAC_DRBG() = default;

HMAC_DRBG::HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                     RandomNumberGenerator& underlying_rng,
                     size_t reseed_interval,
                     size_t max_number_of_bytes_per_request) :
      Stateful_RNG(underlying_rng, reseed_interval),
      m_mac(check_not_null(std::move(prf))),
      m_max_number_of_bytes_per_request(max_number_of_bytes_per_request),
      m_security_level(hmac_drbg_security_level(m_mac->output_length())) {
   check_limits(reseed_interval, max_number_of_bytes_per_request);

   clear();
}

HMAC_DRBG::HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                     RandomNumberGenerator& underlying_rng,
                     Entropy_Sources& entropy_sources,
                     size_t reseed_interval,
                     size_t max_number_of_bytes_per_request) :
      Stateful_RNG(underlying_rng, entropy_sources, reseed_interval),
      m_mac(check_not_null(std::move(prf))),
      m_max_number_of_bytes_per_request(max_number_of_bytes_per_request),
      m_security_level(hmac_drbg_security_level(m_mac->output_length())) {
   check_limits(reseed_interval, max_number_of_bytes_per_request);

   clear();
}

HMAC_DRBG::HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf,
                     Entropy_Sources& entropy_sources,
                     size_t reseed_interval,
                     size_t max_number_of_bytes_per_request) :
      Stateful_RNG(entropy_sources, reseed_interval),
      m_mac(check_not_null(std::move(prf))),
      m_max_number_of_bytes_per_request(max_number_of_bytes_per_request),
      m_security_level(hmac_drbg_security_level(m_mac->output_length())) {
   check_limits(reseed_interval, max_number_of_bytes_per_request);

   clear();
}

HMAC_DRBG::HMAC_DRBG(std::unique_ptr<MessageAuthenticationCode> prf) :
      m_mac(check_not_null(std::move(prf))),
      m_max_number_of_bytes_per_request(64 * 1024),
      m_security_level(hmac_drbg_security_level(m_mac->output_length())) {
   clear();
}

HMAC_DRBG::HMAC_DRBG(std::string_view hmac_hash) :
      m_mac(MessageAuthenticationCode::create_or_throw(fmt("HMAC({})", hmac_hash))),
      m_max_number_of_bytes_per_request(64 * 1024),
      m_security_level(hmac_drbg_security_level(m_mac->output_length())) {
   clear();
}

void HMAC_DRBG::clear_state() {
   if(m_V.empty()) {
      const size_t output_length = m_mac->output_length();
      m_V.resize(output_length);
      m_T.resize(output_length);
   }

   std::fill(m_V.begin(), m_V.end(), 0x01);
   m_mac->set_key(std::vector<uint8_t>(m_V.size(), 0x00));
}

std::string HMAC_DRBG::name() const {
   return fmt("HMAC_DRBG({})", m_mac->name());
}

/*
* HMAC_DRBG generation
* See NIST SP800-90A section 10.1.2.5
*/
void HMAC_DRBG::generate_output(std::span<uint8_t> output, std::span<const uint8_t> input) {
   // This is an internal function, callers should have validated this beforehand
   BOTAN_ASSERT_NOMSG(!output.empty());

   if(!input.empty()) {
      update(input);
   }

   while(!output.empty()) {
      const size_t to_copy = std::min(output.size(), m_V.size());
      m_mac->update(m_V);
      m_mac->final(m_V);
      copy_mem(output.data(), m_V.data(), to_copy);

      output = output.subspan(to_copy);
   }

   update(input);
}

/*
* Reset V and the mac key with new values
* See NIST SP800-90A section 10.1.2.2
*/
void HMAC_DRBG::update(std::span<const uint8_t> input) {
   m_mac->update(m_V);
   m_mac->update(0x00);
   if(!input.empty()) {
      m_mac->update(input);
   }
   m_mac->final(m_T);
   m_mac->set_key(m_T);

   m_mac->update(m_V);
   m_mac->final(m_V);

   if(!input.empty()) {
      m_mac->update(m_V);
      m_mac->update(0x01);
      m_mac->update(input);
      m_mac->final(m_T);
      m_mac->set_key(m_T);

      m_mac->update(m_V);
      m_mac->final(m_V);
   }
}

size_t HMAC_DRBG::security_level() const {
   return m_security_level;
}
}  // namespace Botan
/*
* KDF Retrieval
* (C) 1999-2007 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_HKDF)
#endif

#if defined(BOTAN_HAS_KDF1)
#endif

#if defined(BOTAN_HAS_KDF2)
#endif

#if defined(BOTAN_HAS_KDF1_18033)
#endif

#if defined(BOTAN_HAS_TLS_V12_PRF)
#endif

#if defined(BOTAN_HAS_X942_PRF)
#endif

#if defined(BOTAN_HAS_SP800_108)
#endif

#if defined(BOTAN_HAS_SP800_56A)
#endif

#if defined(BOTAN_HAS_SP800_56C)
#endif

namespace Botan {

namespace {

template <typename KDF_Type, typename... ParamTs>
std::unique_ptr<KDF> kdf_create_mac_or_hash(std::string_view nm, ParamTs&&... params) {
   if(auto mac = MessageAuthenticationCode::create(fmt("HMAC({})", nm))) {
      return std::make_unique<KDF_Type>(std::move(mac), std::forward<ParamTs>(params)...);
   }

   if(auto mac = MessageAuthenticationCode::create(nm)) {
      return std::make_unique<KDF_Type>(std::move(mac), std::forward<ParamTs>(params)...);
   }

   return nullptr;
}

}  // namespace

std::unique_ptr<KDF> KDF::create(std::string_view algo_spec, std::string_view provider) {
   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_HKDF)
   if(req.algo_name() == "HKDF" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<HKDF>(req.arg(0));
      }
   }

   if(req.algo_name() == "HKDF-Extract" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<HKDF_Extract>(req.arg(0));
      }
   }

   if(req.algo_name() == "HKDF-Expand" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<HKDF_Expand>(req.arg(0));
      }
   }
#endif

#if defined(BOTAN_HAS_KDF2)
   if(req.algo_name() == "KDF2" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto hash = HashFunction::create(req.arg(0))) {
            return std::make_unique<KDF2>(std::move(hash));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_KDF1_18033)
   if(req.algo_name() == "KDF1-18033" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto hash = HashFunction::create(req.arg(0))) {
            return std::make_unique<KDF1_18033>(std::move(hash));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_KDF1)
   if(req.algo_name() == "KDF1" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto hash = HashFunction::create(req.arg(0))) {
            return std::make_unique<KDF1>(std::move(hash));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_TLS_V12_PRF)
   if(req.algo_name() == "TLS-12-PRF" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<TLS_12_PRF>(req.arg(0));
      }
   }
#endif

#if defined(BOTAN_HAS_X942_PRF)
   if(req.algo_name() == "X9.42-PRF" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         return std::make_unique<X942_PRF>(req.arg(0));
      }
   }
#endif

#if defined(BOTAN_HAS_SP800_108)
   if(req.algo_name() == "SP800-108-Counter" && req.arg_count_between(1, 3)) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<SP800_108_Counter>(
            req.arg(0), req.arg_as_integer(1, 32), req.arg_as_integer(2, 32));
      }
   }

   if(req.algo_name() == "SP800-108-Feedback" && req.arg_count_between(1, 3)) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<SP800_108_Feedback>(
            req.arg(0), req.arg_as_integer(1, 32), req.arg_as_integer(2, 32));
      }
   }

   if(req.algo_name() == "SP800-108-Pipeline" && req.arg_count_between(1, 3)) {
      if(provider.empty() || provider == "base") {
         return kdf_create_mac_or_hash<SP800_108_Pipeline>(
            req.arg(0), req.arg_as_integer(1, 32), req.arg_as_integer(2, 32));
      }
   }
#endif

#if defined(BOTAN_HAS_SP800_56A)
   if(req.algo_name() == "SP800-56A" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto hash = HashFunction::create(req.arg(0))) {
            return std::make_unique<SP800_56C_One_Step_Hash>(std::move(hash));
         }
         if(req.arg(0) == "KMAC-128") {
            return std::make_unique<SP800_56C_One_Step_KMAC128>();
         }
         if(req.arg(0) == "KMAC-256") {
            return std::make_unique<SP800_56C_One_Step_KMAC256>();
         }
         if(auto mac = MessageAuthenticationCode::create(req.arg(0))) {
            return std::make_unique<SP800_56C_One_Step_HMAC>(std::move(mac));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_SP800_56C)
   if(req.algo_name() == "SP800-56C" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         std::unique_ptr<KDF> exp(kdf_create_mac_or_hash<SP800_108_Feedback>(req.arg(0), 32, 32));
         if(exp) {
            if(auto mac = MessageAuthenticationCode::create(fmt("HMAC({})", req.arg(0)))) {
               return std::make_unique<SP800_56C_Two_Step>(std::move(mac), std::move(exp));
            }

            if(auto mac = MessageAuthenticationCode::create(req.arg(0))) {
               return std::make_unique<SP800_56C_Two_Step>(std::move(mac), std::move(exp));
            }
         }
      }
   }
#endif

   BOTAN_UNUSED(req);
   BOTAN_UNUSED(provider);

   return nullptr;
}

//static
std::unique_ptr<KDF> KDF::create_or_throw(std::string_view algo, std::string_view provider) {
   if(auto kdf = KDF::create(algo, provider)) {
      return kdf;
   }
   throw Lookup_Error("KDF", algo, provider);
}

std::vector<std::string> KDF::providers(std::string_view algo_spec) {
   return probe_providers_of<KDF>(algo_spec);
}

//static
std::span<const uint8_t> KDF::_as_span(std::string_view s) {
   return as_span_of_bytes(s);
}

}  // namespace Botan
/*
* Message Authentication Code base class
* (C) 1999-2008 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CMAC)
#endif

#if defined(BOTAN_HAS_GMAC)
#endif

#if defined(BOTAN_HAS_HMAC)
#endif

#if defined(BOTAN_HAS_POLY1305)
#endif

#if defined(BOTAN_HAS_SIPHASH)
#endif

#if defined(BOTAN_HAS_ANSI_X919_MAC)
#endif

#if defined(BOTAN_HAS_BLAKE2BMAC)
#endif

#if defined(BOTAN_HAS_KMAC)
#endif

namespace Botan {

std::unique_ptr<MessageAuthenticationCode> MessageAuthenticationCode::create(std::string_view algo_spec,
                                                                             std::string_view provider) {
   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_BLAKE2BMAC)
   if(req.algo_name() == "Blake2b" || req.algo_name() == "BLAKE2b") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<BLAKE2bMAC>(req.arg_as_integer(0, 512));
      }
   }
#endif

#if defined(BOTAN_HAS_GMAC)
   if(req.algo_name() == "GMAC" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto bc = BlockCipher::create(req.arg(0))) {
            return std::make_unique<GMAC>(std::move(bc));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_HMAC)
   if(req.algo_name() == "HMAC" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto hash = HashFunction::create(req.arg(0))) {
            return std::make_unique<HMAC>(std::move(hash));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_POLY1305)
   if(req.algo_name() == "Poly1305" && req.arg_count() == 0) {
      if(provider.empty() || provider == "base") {
         return std::make_unique<Poly1305>();
      }
   }
#endif

#if defined(BOTAN_HAS_SIPHASH)
   if(req.algo_name() == "SipHash") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<SipHash>(req.arg_as_integer(0, 2), req.arg_as_integer(1, 4));
      }
   }
#endif

#if defined(BOTAN_HAS_CMAC)
   if((req.algo_name() == "CMAC" || req.algo_name() == "OMAC") && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto bc = BlockCipher::create(req.arg(0))) {
            return std::make_unique<CMAC>(std::move(bc));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_ANSI_X919_MAC)
   if(req.algo_name() == "X9.19-MAC") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<ANSI_X919_MAC>();
      }
   }
#endif

#if defined(BOTAN_HAS_KMAC)
   if(req.algo_name() == "KMAC-128") {
      if(provider.empty() || provider == "base") {
         if(req.arg_count() != 1) {
            throw Invalid_Argument(
               "invalid algorithm specification for KMAC-128: need exactly one argument for output bit length");
         }
         return std::make_unique<KMAC128>(req.arg_as_integer(0));
      }
   }

   if(req.algo_name() == "KMAC-256") {
      if(provider.empty() || provider == "base") {
         if(req.arg_count() != 1) {
            throw Invalid_Argument(
               "invalid algorithm specification for KMAC-256: need exactly one argument for output bit length");
         }
         return std::make_unique<KMAC256>(req.arg_as_integer(0));
      }
   }
#endif

   BOTAN_UNUSED(req);
   BOTAN_UNUSED(provider);

   return nullptr;
}

std::vector<std::string> MessageAuthenticationCode::providers(std::string_view algo_spec) {
   return probe_providers_of<MessageAuthenticationCode>(algo_spec);
}

//static
std::unique_ptr<MessageAuthenticationCode> MessageAuthenticationCode::create_or_throw(std::string_view algo,
                                                                                      std::string_view provider) {
   if(auto mac = MessageAuthenticationCode::create(algo, provider)) {
      return mac;
   }
   throw Lookup_Error("MAC", algo, provider);
}

/*
* Default (deterministic) MAC verification operation
*/
bool MessageAuthenticationCode::verify_mac_result(std::span<const uint8_t> mac) {
   secure_vector<uint8_t> our_mac = final();

   if(our_mac.size() != mac.size()) {
      return false;
   }

   return CT::is_equal(our_mac.data(), mac.data(), mac.size()).as_bool();
}

}  // namespace Botan
/*
* Cipher Modes
* (C) 2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_BLOCK_CIPHER)
#endif

#if defined(BOTAN_HAS_AEAD_MODES)
#endif

#if defined(BOTAN_HAS_MODE_CBC)
#endif

#if defined(BOTAN_HAS_MODE_CFB)
#endif

#if defined(BOTAN_HAS_MODE_XTS)
#endif

#if defined(BOTAN_HAS_COMMONCRYPTO)
#endif

namespace Botan {

std::unique_ptr<Cipher_Mode> Cipher_Mode::create_or_throw(std::string_view algo,
                                                          Cipher_Dir direction,
                                                          std::string_view provider) {
   if(auto mode = Cipher_Mode::create(algo, direction, provider)) {
      return mode;
   }

   throw Lookup_Error("Cipher mode", algo, provider);
}

std::unique_ptr<Cipher_Mode> Cipher_Mode::create(std::string_view algo,
                                                 Cipher_Dir direction,
                                                 std::string_view provider) {
#if defined(BOTAN_HAS_COMMONCRYPTO)
   if(provider.empty() || provider == "commoncrypto") {
      if(auto cm = make_commoncrypto_cipher_mode(algo, direction))
         return cm;

      if(!provider.empty())
         return nullptr;
   }
#endif

   if(provider != "base" && !provider.empty()) {
      return nullptr;
   }

#if defined(BOTAN_HAS_STREAM_CIPHER)
   if(auto sc = StreamCipher::create(algo)) {
      return std::make_unique<Stream_Cipher_Mode>(std::move(sc));
   }
#endif

#if defined(BOTAN_HAS_AEAD_MODES)
   if(auto aead = AEAD_Mode::create(algo, direction)) {
      return aead;
   }
#endif

   if(algo.find('/') != std::string::npos) {
      const std::vector<std::string> algo_parts = split_on(algo, '/');
      if(algo_parts.size() < 2) {
         return std::unique_ptr<Cipher_Mode>();
      }
      const std::string_view cipher_name = algo_parts[0];
      const std::vector<std::string> mode_info = parse_algorithm_name(algo_parts[1]);

      if(mode_info.empty()) {
         return std::unique_ptr<Cipher_Mode>();
      }

      std::ostringstream mode_name;

      mode_name << mode_info[0] << '(' << cipher_name;
      for(size_t i = 1; i < mode_info.size(); ++i) {
         mode_name << ',' << mode_info[i];
      }
      for(size_t i = 2; i < algo_parts.size(); ++i) {
         mode_name << ',' << algo_parts[i];
      }
      mode_name << ')';

      return Cipher_Mode::create(mode_name.str(), direction, provider);
   }

#if defined(BOTAN_HAS_BLOCK_CIPHER)

   const SCAN_Name spec(algo);

   if(spec.arg_count() == 0) {
      return std::unique_ptr<Cipher_Mode>();
   }

   auto bc = BlockCipher::create(spec.arg(0), provider);

   if(!bc) {
      return std::unique_ptr<Cipher_Mode>();
   }

   #if defined(BOTAN_HAS_MODE_CBC)
   if(spec.algo_name() == "CBC") {
      const std::string padding = spec.arg(1, "PKCS7");

      if(padding == "CTS") {
         if(direction == Cipher_Dir::Encryption) {
            return std::make_unique<CTS_Encryption>(std::move(bc));
         } else {
            return std::make_unique<CTS_Decryption>(std::move(bc));
         }
      } else {
         auto pad = BlockCipherModePaddingMethod::create(padding);

         if(pad) {
            if(direction == Cipher_Dir::Encryption) {
               return std::make_unique<CBC_Encryption>(std::move(bc), std::move(pad));
            } else {
               return std::make_unique<CBC_Decryption>(std::move(bc), std::move(pad));
            }
         }
      }
   }
   #endif

   #if defined(BOTAN_HAS_MODE_XTS)
   if(spec.algo_name() == "XTS") {
      if(direction == Cipher_Dir::Encryption) {
         return std::make_unique<XTS_Encryption>(std::move(bc));
      } else {
         return std::make_unique<XTS_Decryption>(std::move(bc));
      }
   }
   #endif

   #if defined(BOTAN_HAS_MODE_CFB)
   if(spec.algo_name() == "CFB") {
      const size_t feedback_bits = spec.arg_as_integer(1, 8 * bc->block_size());
      if(direction == Cipher_Dir::Encryption) {
         return std::make_unique<CFB_Encryption>(std::move(bc), feedback_bits);
      } else {
         return std::make_unique<CFB_Decryption>(std::move(bc), feedback_bits);
      }
   }
   #endif

#endif

   return std::unique_ptr<Cipher_Mode>();
}

//static
std::vector<std::string> Cipher_Mode::providers(std::string_view algo_spec) {
   const std::vector<std::string>& possible = {"base", "commoncrypto"};
   std::vector<std::string> providers;
   for(auto&& prov : possible) {
      auto mode = Cipher_Mode::create(algo_spec, Cipher_Dir::Encryption, prov);
      if(mode) {
         providers.push_back(prov);  // available
      }
   }
   return providers;
}

}  // namespace Botan
/*
* (C) 2011,2017 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

std::vector<uint8_t> raw_nist_key_wrap(const uint8_t input[], size_t input_len, const BlockCipher& bc, uint64_t ICV) {
   const size_t n = input_len / 8 + (input_len % 8 != 0 ? 1 : 0);

   secure_vector<uint8_t> R(mul_or_throw<size_t>(8, n + 1, "NIST key wrap input too large"));
   secure_vector<uint8_t> A(16);

   store_be(ICV, A.data());

   copy_mem(&R[8], input, input_len);

   for(size_t j = 0; j <= 5; ++j) {
      for(size_t i = 1; i <= n; ++i) {
         const uint32_t t = static_cast<uint32_t>((n * j) + i);

         copy_mem(&A[8], &R[8 * i], 8);

         bc.encrypt(A.data());
         copy_mem(&R[8 * i], &A[8], 8);

         uint8_t t_buf[4] = {0};
         store_be(t, t_buf);
         xor_buf(&A[4], t_buf, 4);
      }
   }

   copy_mem(R.data(), A.data(), 8);

   return std::vector<uint8_t>(R.begin(), R.end());
}

secure_vector<uint8_t> raw_nist_key_unwrap(const uint8_t input[],
                                           size_t input_len,
                                           const BlockCipher& bc,
                                           uint64_t& ICV_out) {
   if(input_len < 16 || input_len % 8 != 0) {
      throw Invalid_Argument("Bad input size for NIST key unwrap");
   }

   const size_t n = (input_len - 8) / 8;

   secure_vector<uint8_t> R(n * 8);
   secure_vector<uint8_t> A(16);

   for(size_t i = 0; i != 8; ++i) {
      A[i] = input[i];
   }

   copy_mem(R.data(), input + 8, input_len - 8);

   for(size_t j = 0; j <= 5; ++j) {
      for(size_t i = n; i != 0; --i) {
         const uint32_t t = static_cast<uint32_t>((5 - j) * n + i);

         uint8_t t_buf[4] = {0};
         store_be(t, t_buf);

         xor_buf(&A[4], t_buf, 4);

         copy_mem(&A[8], &R[8 * (i - 1)], 8);

         bc.decrypt(A.data());

         copy_mem(&R[8 * (i - 1)], &A[8], 8);
      }
   }

   ICV_out = load_be<uint64_t>(A.data(), 0);

   return R;
}

}  // namespace

std::vector<uint8_t> nist_key_wrap(const uint8_t input[], size_t input_len, const BlockCipher& bc) {
   if(bc.block_size() != 16) {
      throw Invalid_Argument("NIST key wrap algorithm requires a 128-bit cipher");
   }

   if(input_len == 0 || input_len % 8 != 0) {
      throw Invalid_Argument("Bad input size for NIST key wrap");
   }

   const uint64_t ICV = 0xA6A6A6A6A6A6A6A6;

   if(input_len == 8) {
      /*
      * Special case for small inputs: if input == 8 bytes just use ECB
      * (see RFC 3394 Section 2)
      */
      std::vector<uint8_t> block(16);
      store_be(ICV, block.data());
      copy_mem(block.data() + 8, input, input_len);
      bc.encrypt(block);
      return block;
   } else {
      return raw_nist_key_wrap(input, input_len, bc, ICV);
   }
}

secure_vector<uint8_t> nist_key_unwrap(const uint8_t input[], size_t input_len, const BlockCipher& bc) {
   if(bc.block_size() != 16) {
      throw Invalid_Argument("NIST key wrap algorithm requires a 128-bit cipher");
   }

   if(input_len < 16 || input_len % 8 != 0) {
      throw Invalid_Argument("Bad input size for NIST key unwrap");
   }

   const uint64_t ICV = 0xA6A6A6A6A6A6A6A6;

   uint64_t ICV_out = 0;
   secure_vector<uint8_t> R;

   if(input_len == 16) {
      secure_vector<uint8_t> block(input, input + input_len);
      bc.decrypt(block);

      ICV_out = load_be<uint64_t>(block.data(), 0);
      R.resize(8);
      copy_mem(R.data(), block.data() + 8, 8);
   } else {
      R = raw_nist_key_unwrap(input, input_len, bc, ICV_out);
   }

   if(ICV_out != ICV) {
      throw Invalid_Authentication_Tag("NIST key unwrap failed");
   }

   return R;
}

std::vector<uint8_t> nist_key_wrap_padded(const uint8_t input[], size_t input_len, const BlockCipher& bc) {
   if(bc.block_size() != 16) {
      throw Invalid_Argument("NIST key wrap algorithm requires a 128-bit cipher");
   }

   if(input_len == 0) {
      throw Invalid_Argument("NIST KWP cannot accept empty inputs");
   }

   const uint64_t ICV = 0xA65959A600000000 | static_cast<uint32_t>(input_len);

   if(input_len <= 8) {
      /*
      * Special case for small inputs: if input <= 8 bytes just use ECB
      */
      std::vector<uint8_t> block(16);
      store_be(ICV, block.data());
      copy_mem(block.data() + 8, input, input_len);
      bc.encrypt(block);
      return block;
   } else {
      return raw_nist_key_wrap(input, input_len, bc, ICV);
   }
}

secure_vector<uint8_t> nist_key_unwrap_padded(const uint8_t input[], size_t input_len, const BlockCipher& bc) {
   if(bc.block_size() != 16) {
      throw Invalid_Argument("NIST key wrap algorithm requires a 128-bit cipher");
   }

   if(input_len < 16 || input_len % 8 != 0) {
      throw Invalid_Argument("Bad input size for NIST key unwrap");
   }

   uint64_t ICV_out = 0;
   secure_vector<uint8_t> R;

   if(input_len == 16) {
      secure_vector<uint8_t> block(input, input + input_len);
      bc.decrypt(block);

      ICV_out = load_be<uint64_t>(block.data(), 0);
      R.resize(8);
      copy_mem(R.data(), block.data() + 8, 8);
   } else {
      R = raw_nist_key_unwrap(input, input_len, bc, ICV_out);
   }

   /*
   The padded key wrap ICV is 0xA65959A6 || uint32(plaintext_length).

   We know the expected ICV almost entirely: the top 32 bits are the
   fixed constant and the bottom 32 bits encode the original plaintext
   length, which is R.size() minus 0 to 7 bytes of padding. Compute
   the ICV we'd expect for the zero-padding case and subtract ICV_out;
   for a valid unwrap the difference is at most 7, and equals the padding.
   For an invalid unwrap the unsigned subtraction wraps to a value > 7
   (checked below), so the modular arithmetic here is intentional.
   */
   const uint64_t expected_ICV_max = 0xA65959A600000000 | static_cast<uint32_t>(R.size());
   const uint64_t padding = expected_ICV_max - ICV_out;

   if(padding > 7) {
      throw Invalid_Authentication_Tag("NIST key unwrap failed");
   }

   // Verify padding bytes are zero
   const uint64_t last_block = load_be<uint64_t>(R.data() + R.size() - 8, 0);
   const uint64_t padding_mask = (static_cast<uint64_t>(1) << (padding * 8)) - 1;
   if((last_block & padding_mask) != 0) {
      throw Invalid_Authentication_Tag("NIST key unwrap failed");
   }

   R.resize(R.size() - static_cast<size_t>(padding));
   return R;
}

}  // namespace Botan
/*
* OS and machine specific utility functions
* (C) 2015,2016,2017,2018 Jack Lloyd
* (C) 2016 Daniel Neus
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

#include <chrono>
#include <cstdlib>
#include <iomanip>

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   #include <errno.h>
   #include <pthread.h>
   #include <setjmp.h>
   #include <signal.h>
   #include <sys/mman.h>
   #include <sys/resource.h>
   #include <sys/types.h>
   #include <termios.h>
   #include <unistd.h>
   #undef B0
#endif

#if defined(BOTAN_TARGET_OS_IS_EMSCRIPTEN)
   #include <emscripten/emscripten.h>
#endif

#if defined(BOTAN_TARGET_OS_HAS_GETAUXVAL) || defined(BOTAN_TARGET_OS_HAS_ELF_AUX_INFO)
   #include <sys/auxv.h>
#endif

#if defined(BOTAN_TARGET_OS_HAS_WIN32)
   #define NOMINMAX 1
   #define _WINSOCKAPI_  // stop windows.h including winsock.h
   #include <windows.h>
   #if defined(BOTAN_BUILD_COMPILER_IS_MSVC)
      #include <libloaderapi.h>
      #include <stringapiset.h>
   #endif
#endif

#if defined(BOTAN_TARGET_OS_IS_IOS) || defined(BOTAN_TARGET_OS_IS_MACOS)
   #include <mach/vm_statistics.h>
   #include <sys/sysctl.h>
   #include <sys/types.h>
#endif

#if defined(BOTAN_TARGET_OS_HAS_PRCTL)
   #include <sys/prctl.h>
#endif

#if defined(BOTAN_TARGET_OS_IS_FREEBSD) || defined(BOTAN_TARGET_OS_IS_OPENBSD) || defined(BOTAN_TARGET_OS_IS_DRAGONFLY)
   #include <pthread_np.h>
#endif

#if defined(BOTAN_TARGET_OS_IS_HAIKU)
   #include <kernel/OS.h>
#endif

namespace Botan {

uint32_t OS::get_process_id() {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   return ::getpid();
#elif defined(BOTAN_TARGET_OS_HAS_WIN32)
   return ::GetCurrentProcessId();
#elif defined(BOTAN_TARGET_OS_IS_LLVM) || defined(BOTAN_TARGET_OS_IS_NONE)
   return 0;  // truly no meaningful value
#else
   #error "Missing get_process_id"
#endif
}

namespace {

#if defined(BOTAN_TARGET_OS_HAS_GETAUXVAL) || defined(BOTAN_TARGET_OS_HAS_ELF_AUX_INFO)
   #define BOTAN_TARGET_HAS_AUXVAL_INTERFACE
#endif

std::optional<unsigned long> auxval_hwcap() {
#if defined(AT_HWCAP)
   return AT_HWCAP;
#elif defined(BOTAN_TARGET_HAS_AUXVAL_INTERFACE)
   // If the value is not defined in a header we can see,
   // but auxval is supported, return the Linux/Android value
   return 16;
#else
   return {};
#endif
}

std::optional<unsigned long> auxval_hwcap2() {
#if defined(AT_HWCAP2)
   return AT_HWCAP2;
#elif defined(BOTAN_TARGET_HAS_AUXVAL_INTERFACE)
   // If the value is not defined in a header we can see,
   // but auxval is supported, return the Linux/Android value
   return 26;
#else
   return {};
#endif
}

std::optional<unsigned long> get_auxval(std::optional<unsigned long> id) {
   if(id) {
#if defined(BOTAN_TARGET_OS_HAS_GETAUXVAL)
      return ::getauxval(*id);
#elif defined(BOTAN_TARGET_OS_HAS_ELF_AUX_INFO)
      unsigned long auxinfo = 0;
      if(::elf_aux_info(static_cast<int>(*id), &auxinfo, sizeof(auxinfo)) == 0) {
         return auxinfo;
      }
#endif
   }

   return {};
}

}  // namespace

std::optional<std::pair<unsigned long, unsigned long>> OS::get_auxval_hwcap() {
   if(const auto hwcap = get_auxval(auxval_hwcap())) {
      // If hwcap worked/was valid, we don't require hwcap2 to also
      // succeed but instead will return zeros if it failed.
      auto hwcap2 = get_auxval(auxval_hwcap2()).value_or(0);
      return std::make_pair(*hwcap, hwcap2);
   } else {
      return {};
   }
}

namespace {

/**
* Test if we are currently running with elevated permissions
* eg setuid, setgid, or with POSIX caps set.
*/
bool running_in_privileged_state() {
#if defined(AT_SECURE)
   if(auto at_secure = get_auxval(AT_SECURE)) {
      return at_secure != 0;
   }
#endif

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   return (::getuid() != ::geteuid()) || (::getgid() != ::getegid());
#else
   return false;
#endif
}

}  // namespace

uint64_t OS::get_cpu_cycle_counter() {
   uint64_t rtc = 0;

#if defined(BOTAN_TARGET_OS_HAS_WIN32)
   LARGE_INTEGER tv;
   ::QueryPerformanceCounter(&tv);
   rtc = tv.QuadPart;

#elif defined(BOTAN_USE_GCC_INLINE_ASM)

   // NOLINTBEGIN(*-no-assembler)

   #if defined(BOTAN_TARGET_ARCH_IS_X86_64)

   uint32_t rtc_low = 0;   // NOLINT(*-const-correctness) clang-tidy doesn't understand inline asm
   uint32_t rtc_high = 0;  // NOLINT(*-const-correctness) clang-tidy doesn't understand inline asm
   asm volatile("rdtsc" : "=d"(rtc_high), "=a"(rtc_low));
   rtc = (static_cast<uint64_t>(rtc_high) << 32) | rtc_low;

   #elif defined(BOTAN_TARGET_ARCH_IS_X86_FAMILY) && defined(BOTAN_HAS_CPUID)

   if(CPUID::has(CPUID::Feature::RDTSC)) {
      uint32_t rtc_low = 0;
      uint32_t rtc_high = 0;
      asm volatile("rdtsc" : "=d"(rtc_high), "=a"(rtc_low));
      rtc = (static_cast<uint64_t>(rtc_high) << 32) | rtc_low;
   }

   #elif defined(BOTAN_TARGET_ARCH_IS_PPC64)

   for(;;) {
      uint32_t rtc_low = 0;
      uint32_t rtc_high = 0;
      uint32_t rtc_high2 = 0;
      asm volatile("mftbu %0" : "=r"(rtc_high));
      asm volatile("mftb %0" : "=r"(rtc_low));
      asm volatile("mftbu %0" : "=r"(rtc_high2));

      if(rtc_high == rtc_high2) {
         rtc = (static_cast<uint64_t>(rtc_high) << 32) | rtc_low;
         break;
      }
   }

   #elif defined(BOTAN_TARGET_ARCH_IS_ALPHA)
   asm volatile("rpcc %0" : "=r"(rtc));

   #elif defined(BOTAN_TARGET_ARCH_IS_SPARC64) && !defined(BOTAN_TARGET_OS_IS_OPENBSD)
   // OpenBSD does not trap access to the %tick register so we avoid it there
   asm volatile("rd %%tick, %0" : "=r"(rtc));

   #elif defined(BOTAN_TARGET_ARCH_IS_IA64)
   asm volatile("mov %0=ar.itc" : "=r"(rtc));

   #elif defined(BOTAN_TARGET_ARCH_IS_S390X)
   asm volatile("stck 0(%0)" : : "a"(&rtc) : "memory", "cc");

   #elif defined(BOTAN_TARGET_ARCH_IS_HPPA)
   asm volatile("mfctl 16,%0" : "=r"(rtc));  // 64-bit only?

   #else
      //#warning "OS::get_cpu_cycle_counter not implemented"
   #endif

   // NOLINTEND(*-no-assembler)

#endif

   return rtc;
}

size_t OS::get_cpu_available() {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)

   #if defined(_SC_NPROCESSORS_ONLN)
   const long cpu_online = ::sysconf(_SC_NPROCESSORS_ONLN);
   if(cpu_online > 0) {
      return static_cast<size_t>(cpu_online);
   }
   #endif

   #if defined(_SC_NPROCESSORS_CONF)
   const long cpu_conf = ::sysconf(_SC_NPROCESSORS_CONF);
   if(cpu_conf > 0) {
      return static_cast<size_t>(cpu_conf);
   }
   #endif

#endif

#if defined(BOTAN_TARGET_OS_HAS_THREADS)
   // hardware_concurrency is allowed to return 0 if the value is not
   // well defined or not computable.
   const size_t hw_concur = std::thread::hardware_concurrency();

   if(hw_concur > 0) {
      return hw_concur;
   }
#endif

   return 1;
}

uint64_t OS::get_high_resolution_clock() {
   if(const uint64_t cpu_clock = OS::get_cpu_cycle_counter()) {
      return cpu_clock;
   }

#if defined(BOTAN_TARGET_OS_IS_EMSCRIPTEN)
   return emscripten_get_now();
#endif

   /*
   If we got here either we either don't have an asm instruction
   above, or (for x86) RDTSC is not available at runtime. Try some
   clock_gettimes and return the first one that works, or otherwise
   fall back to std::chrono.
   */

#if defined(BOTAN_TARGET_OS_HAS_CLOCK_GETTIME)

   // The ordering here is somewhat arbitrary...
   const clockid_t clock_types[] = {
   #if defined(CLOCK_MONOTONIC_HR)
      CLOCK_MONOTONIC_HR,
   #endif
   #if defined(CLOCK_MONOTONIC_RAW)
      CLOCK_MONOTONIC_RAW,
   #endif
   #if defined(CLOCK_MONOTONIC)
      CLOCK_MONOTONIC,
   #endif
   #if defined(CLOCK_PROCESS_CPUTIME_ID)
      CLOCK_PROCESS_CPUTIME_ID,
   #endif
   #if defined(CLOCK_THREAD_CPUTIME_ID)
      CLOCK_THREAD_CPUTIME_ID,
   #endif
   };

   for(const clockid_t clock : clock_types) {
      struct timespec ts {};

      if(::clock_gettime(clock, &ts) == 0) {
         return (static_cast<uint64_t>(ts.tv_sec) * 1000000000) + static_cast<uint64_t>(ts.tv_nsec);
      }
   }
#endif

#if defined(BOTAN_TARGET_OS_HAS_SYSTEM_CLOCK)
   // Plain C++11 fallback
   auto now = std::chrono::high_resolution_clock::now().time_since_epoch();
   return std::chrono::duration_cast<std::chrono::nanoseconds>(now).count();
#else
   return 0;
#endif
}

uint64_t OS::get_system_timestamp_ns() {
#if defined(BOTAN_TARGET_OS_HAS_CLOCK_GETTIME)
   struct timespec ts {};

   if(::clock_gettime(CLOCK_REALTIME, &ts) == 0) {
      return (static_cast<uint64_t>(ts.tv_sec) * 1000000000) + static_cast<uint64_t>(ts.tv_nsec);
   }
#endif

#if defined(BOTAN_TARGET_OS_HAS_SYSTEM_CLOCK)
   auto now = std::chrono::system_clock::now().time_since_epoch();
   return std::chrono::duration_cast<std::chrono::nanoseconds>(now).count();
#else
   throw Not_Implemented("OS::get_system_timestamp_ns this system does not support a clock");
#endif
}

std::string OS::format_time(time_t time, const std::string& format) {
   std::tm tm{};

#if defined(BOTAN_TARGET_OS_HAS_WIN32)
   if(::localtime_s(&tm, &time) != 0) {
      throw Encoding_Error("Could not convert time_t to localtime");
   }
#elif defined(BOTAN_TARGET_OS_HAS_POSIX1)
   if(::localtime_r(&time, &tm) == nullptr) {
      throw Encoding_Error("Could not convert time_t to localtime");
   }
#else
   if(auto tmp = std::localtime(&time)) {
      tm = *tmp;
   } else {
      throw Encoding_Error("Could not convert time_t to localtime");
   }
#endif

   std::ostringstream oss;
   oss << std::put_time(&tm, format.c_str());
   return oss.str();
}

size_t OS::system_page_size() {
   const size_t default_page_size = 4096;

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   const long p = ::sysconf(_SC_PAGESIZE);
   if(p > 1) {
      return static_cast<size_t>(p);
   } else {
      return default_page_size;
   }
#elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
   BOTAN_UNUSED(default_page_size);
   SYSTEM_INFO sys_info;
   ::GetSystemInfo(&sys_info);
   return sys_info.dwPageSize;
#else
   return default_page_size;
#endif
}

size_t OS::get_memory_locking_limit() {
   /*
   * Linux defaults to only 64 KiB of mlockable memory per process (too small)
   * but BSDs offer a small fraction of total RAM (more than we need). Bound the
   * total mlock size to 512 KiB which is enough to run the entire test suite
   * without spilling to non-mlock memory (and thus presumably also enough for
   * many useful programs), but small enough that we should not cause problems
   * even if many processes are mlocking on the same machine.
   */
   const size_t max_locked_kb = 512;

   /*
   * If RLIMIT_MEMLOCK is not defined, likely the OS does not support
   * unprivileged mlock calls.
   */
#if defined(RLIMIT_MEMLOCK) && defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)
   const size_t mlock_requested =
      std::min<size_t>(read_env_variable_sz("BOTAN_MLOCK_POOL_SIZE", max_locked_kb), max_locked_kb);

   if(mlock_requested > 0) {
      struct ::rlimit limits {};

      ::getrlimit(RLIMIT_MEMLOCK, &limits);

      if(limits.rlim_cur < limits.rlim_max) {
         limits.rlim_cur = limits.rlim_max;
         ::setrlimit(RLIMIT_MEMLOCK, &limits);
         ::getrlimit(RLIMIT_MEMLOCK, &limits);
      }

      return std::min<size_t>(limits.rlim_cur, mlock_requested * 1024);
   }

#elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
   const size_t mlock_requested =
      std::min<size_t>(read_env_variable_sz("BOTAN_MLOCK_POOL_SIZE", max_locked_kb), max_locked_kb);

   SIZE_T working_min = 0, working_max = 0;
   if(!::GetProcessWorkingSetSize(::GetCurrentProcess(), &working_min, &working_max)) {
      return 0;
   }

   // According to Microsoft MSDN:
   // The maximum number of pages that a process can lock is equal to the number of pages in its minimum working set minus a small overhead
   // In the book "Windows Internals Part 2": the maximum lockable pages are minimum working set size - 8 pages
   // But the information in the book seems to be inaccurate/outdated
   // I've tested this on Windows 8.1 x64, Windows 10 x64 and Windows 7 x86
   // On all three OS the value is 11 instead of 8
   const size_t overhead = OS::system_page_size() * 11;
   if(working_min > overhead) {
      const size_t lockable_bytes = working_min - overhead;
      return std::min<size_t>(lockable_bytes, mlock_requested * 1024);
   }
#else
   // Not supported on this platform
   BOTAN_UNUSED(max_locked_kb);
#endif

   return 0;
}

bool OS::read_env_variable(std::string& value_out, std::string_view name_view) {
   value_out = "";

   if(running_in_privileged_state()) {
      return false;
   }

#if defined(BOTAN_TARGET_OS_HAS_WIN32) && \
   (defined(BOTAN_BUILD_COMPILER_IS_MSVC) || defined(BOTAN_BUILD_COMPILER_IS_CLANGCL))
   const std::string name(name_view);
   char val[128] = {0};
   size_t req_size = 0;
   if(getenv_s(&req_size, val, sizeof(val), name.c_str()) == 0) {
      // Microsoft's implementation always writes a terminating \0,
      // and includes it in the reported length of the environment variable
      // if a value exists.
      if(req_size > 0 && val[req_size - 1] == '\0') {
         value_out = std::string(val);
      } else {
         value_out = std::string(val, req_size);
      }
      return true;
   }
#else
   const std::string name(name_view);
   if(const char* val = std::getenv(name.c_str())) {
      value_out = val;
      return true;
   }
#endif

   return false;
}

size_t OS::read_env_variable_sz(std::string_view name, size_t def) {
   std::string value;
   if(read_env_variable(value, name) && !value.empty()) {
      if(const auto sz = parse_sz(value)) {
         return *sz;
      }
   }

   return def;
}

#if defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)

namespace {

int get_locked_fd() {
   #if defined(BOTAN_TARGET_OS_IS_IOS) || defined(BOTAN_TARGET_OS_IS_MACOS)
   // On Darwin, tagging anonymous pages allows vmmap to track these.
   // Allowed from 240 to 255 for userland applications
   static constexpr int default_locked_fd = 255;
   int locked_fd = default_locked_fd;

   if(size_t locked_fdl = OS::read_env_variable_sz("BOTAN_LOCKED_FD", default_locked_fd)) {
      if(locked_fdl < 240 || locked_fdl > 255) {
         locked_fdl = default_locked_fd;
      }
      locked_fd = static_cast<int>(locked_fdl);
   }
   return VM_MAKE_TAG(locked_fd);
   #else
   return -1;
   #endif
}

int mmap_flags() {
   int flags = MAP_PRIVATE;

   #if defined(MAP_ANONYMOUS)
   flags |= MAP_ANONYMOUS;
   #elif defined(MAP_ANON)
   flags |= MAP_ANON;
   #endif

   #if defined(MAP_CONCEAL)
   flags |= MAP_CONCEAL;
   #elif defined(MAP_NOCORE)
   flags |= MAP_NOCORE;
   #endif

   return flags;
}

int mmap_prot() {
   int prot = PROT_READ | PROT_WRITE;  // NOLINT(*-const-correctness)

   #if defined(PROT_MAX)
   prot |= PROT_MAX(prot);
   #endif

   return prot;
}

}  // namespace

#endif

std::vector<void*> OS::allocate_locked_pages(size_t count) {
   std::vector<void*> result;

#if(defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)) || \
   defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)

   result.reserve(count);

   const size_t page_size = OS::system_page_size();

   #if defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)
   static const int locked_fd = get_locked_fd();
   #endif

   for(size_t i = 0; i != count; ++i) {
      void* ptr = nullptr;

   #if defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)
      ptr = ::mmap(nullptr,
                   3 * page_size,
                   mmap_prot(),
                   mmap_flags(),
                   /*fd=*/locked_fd,
                   /*offset=*/0);

      if(ptr == MAP_FAILED) {
         continue;
      }

      // lock the data page
      if(::mlock(static_cast<uint8_t*>(ptr) + page_size, page_size) != 0) {
         ::munmap(ptr, 3 * page_size);
         continue;
      }

      #if defined(MADV_DONTDUMP)
      // we ignore errors here, as DONTDUMP is just a bonus
      ::madvise(static_cast<uint8_t*>(ptr) + page_size, page_size, MADV_DONTDUMP);
      #endif

   #elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
      ptr = ::VirtualAlloc(nullptr, 3 * page_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);

      if(ptr == nullptr)
         continue;

      if(::VirtualLock(static_cast<uint8_t*>(ptr) + page_size, page_size) == 0) {
         ::VirtualFree(ptr, 0, MEM_RELEASE);
         continue;
      }
   #endif

      std::memset(ptr, 0, 3 * page_size);  // zero data page and both guard pages

      // Attempts to name the data page
      page_named(ptr, 3 * page_size);
      // Make guard page preceding the data page
      page_prohibit_access(static_cast<uint8_t*>(ptr));
      // Make guard page following the data page
      page_prohibit_access(static_cast<uint8_t*>(ptr) + 2 * page_size);

      result.push_back(static_cast<uint8_t*>(ptr) + page_size);
   }
#else
   BOTAN_UNUSED(count);
#endif

   return result;
}

void OS::page_allow_access(void* page) {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   const size_t page_size = OS::system_page_size();
   ::mprotect(page, page_size, PROT_READ | PROT_WRITE);
#elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
   const size_t page_size = OS::system_page_size();
   DWORD old_perms = 0;
   ::VirtualProtect(page, page_size, PAGE_READWRITE, &old_perms);
   BOTAN_UNUSED(old_perms);
#else
   BOTAN_UNUSED(page);
#endif
}

void OS::page_prohibit_access(void* page) {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   const size_t page_size = OS::system_page_size();
   ::mprotect(page, page_size, PROT_NONE);
#elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
   const size_t page_size = OS::system_page_size();
   DWORD old_perms = 0;
   ::VirtualProtect(page, page_size, PAGE_NOACCESS, &old_perms);
   BOTAN_UNUSED(old_perms);
#else
   BOTAN_UNUSED(page);
#endif
}

void OS::free_locked_pages(const std::vector<void*>& pages) {
   const size_t page_size = OS::system_page_size();

   for(void* ptr : pages) {
      secure_scrub_memory(ptr, page_size);

      // ptr points to the data page, guard pages are before and after
      page_allow_access(static_cast<uint8_t*>(ptr) - page_size);
      page_allow_access(static_cast<uint8_t*>(ptr) + page_size);

#if defined(BOTAN_TARGET_OS_HAS_POSIX1) && defined(BOTAN_TARGET_OS_HAS_POSIX_MLOCK)
      ::munlock(ptr, page_size);
      ::munmap(static_cast<uint8_t*>(ptr) - page_size, 3 * page_size);
#elif defined(BOTAN_TARGET_OS_HAS_VIRTUAL_LOCK)
      ::VirtualUnlock(ptr, page_size);
      ::VirtualFree(static_cast<uint8_t*>(ptr) - page_size, 0, MEM_RELEASE);
#endif
   }
}

void OS::page_named(void* page, size_t size) {
#if defined(BOTAN_TARGET_OS_HAS_PRCTL) && defined(PR_SET_VMA) && defined(PR_SET_VMA_ANON_NAME)
   static constexpr char name[] = "Botan mlock pool";
   // NOLINTNEXTLINE(*-vararg)
   const int r = prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, reinterpret_cast<uintptr_t>(page), size, name);
   BOTAN_UNUSED(r);
#else
   BOTAN_UNUSED(page, size);
#endif
}

#if defined(BOTAN_TARGET_OS_HAS_THREADS)
void OS::set_thread_name(std::thread& thread, const std::string& name) {
   #if defined(BOTAN_TARGET_OS_IS_LINUX) || defined(BOTAN_TARGET_OS_IS_FREEBSD) || defined(BOTAN_TARGET_OS_IS_DRAGONFLY)
   static_cast<void>(pthread_setname_np(thread.native_handle(), name.c_str()));
   #elif defined(BOTAN_TARGET_OS_IS_OPENBSD)
   static_cast<void>(pthread_set_name_np(thread.native_handle(), name.c_str()));
   #elif defined(BOTAN_TARGET_OS_IS_NETBSD)
   static_cast<void>(pthread_setname_np(thread.native_handle(), "%s", const_cast<char*>(name.c_str())));
   #elif defined(BOTAN_TARGET_OS_HAS_WIN32) && defined(_LIBCPP_HAS_THREAD_API_PTHREAD)
   static_cast<void>(pthread_setname_np(thread.native_handle(), name.c_str()));
   #elif defined(BOTAN_TARGET_OS_HAS_WIN32) && defined(BOTAN_BUILD_COMPILER_IS_MSVC)
   typedef HRESULT(WINAPI * std_proc)(HANDLE, PCWSTR);
   HMODULE kern = GetModuleHandleA("KernelBase.dll");
   std_proc set_thread_name = reinterpret_cast<std_proc>(GetProcAddress(kern, "SetThreadDescription"));
   if(set_thread_name) {
      std::wstring w;
      auto sz = MultiByteToWideChar(CP_UTF8, 0, name.data(), -1, nullptr, 0);
      if(sz > 0) {
         w.resize(sz);
         if(MultiByteToWideChar(CP_UTF8, 0, name.data(), -1, &w[0], sz) > 0) {
            (void)set_thread_name(thread.native_handle(), w.c_str());
         }
      }
   }
   #elif defined(BOTAN_TARGET_OS_IF_HAIKU)
   auto thread_id = get_pthread_thread_id(thread.native_handle());
   static_cast<void>(rename_thread(thread_id, name.c_str()));
   #else
   // TODO other possible oses ?
   // macOs does not seem to allow to name threads other than the current one.
   BOTAN_UNUSED(thread, name);
   #endif
}
#endif

#if defined(BOTAN_TARGET_OS_HAS_POSIX1) && !defined(BOTAN_TARGET_OS_IS_EMSCRIPTEN)

namespace {

// NOLINTNEXTLINE(*-avoid-non-const-global-variables)
::sigjmp_buf g_sigill_jmp_buf;

void botan_sigill_handler(int /*unused*/) {
   siglongjmp(g_sigill_jmp_buf, /*non-zero return value*/ 1);
}

}  // namespace

#endif

int OS::run_cpu_instruction_probe(const std::function<int()>& probe_fn) {
   volatile int probe_result = -3;

#if defined(BOTAN_TARGET_OS_HAS_POSIX1) && !defined(BOTAN_TARGET_OS_IS_EMSCRIPTEN)
   struct sigaction old_sigaction {};

   struct sigaction sigaction {};

   sigaction.sa_handler = botan_sigill_handler;
   sigemptyset(&sigaction.sa_mask);
   sigaction.sa_flags = 0;

   int rc = ::sigaction(SIGILL, &sigaction, &old_sigaction);

   if(rc != 0) {
      throw System_Error("run_cpu_instruction_probe sigaction failed", errno);
   }

   rc = sigsetjmp(g_sigill_jmp_buf, /*save sigs*/ 1);

   if(rc == 0) {
      // first call to sigsetjmp
      probe_result = probe_fn();
   } else if(rc == 1) {
      // non-local return from siglongjmp in signal handler: return error
      probe_result = -1;
   }

   // Restore old SIGILL handler, if any
   rc = ::sigaction(SIGILL, &old_sigaction, nullptr);
   if(rc != 0) {
      throw System_Error("run_cpu_instruction_probe sigaction restore failed", errno);
   }

#else
   BOTAN_UNUSED(probe_fn);
#endif

   return probe_result;
}

std::unique_ptr<OS::Echo_Suppression> OS::suppress_echo_on_terminal() {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   class POSIX_Echo_Suppression final : public Echo_Suppression {
      public:
         POSIX_Echo_Suppression() : m_stdin_fd(fileno(stdin)), m_old_termios{} {
            if(::tcgetattr(m_stdin_fd, &m_old_termios) != 0) {
               throw System_Error("Getting terminal status failed", errno);
            }

            struct termios noecho_flags = m_old_termios;
            noecho_flags.c_lflag &= ~ECHO;
            noecho_flags.c_lflag |= ECHONL;

            if(::tcsetattr(m_stdin_fd, TCSANOW, &noecho_flags) != 0) {
               throw System_Error("Clearing terminal echo bit failed", errno);
            }
         }

         void reenable_echo() override {
            if(m_stdin_fd > 0) {
               if(::tcsetattr(m_stdin_fd, TCSANOW, &m_old_termios) != 0) {
                  throw System_Error("Restoring terminal echo bit failed", errno);
               }
               m_stdin_fd = -1;
            }
         }

         ~POSIX_Echo_Suppression() override {
            try {
               reenable_echo();
            } catch(...) {}
         }

         POSIX_Echo_Suppression(const POSIX_Echo_Suppression& other) = delete;
         POSIX_Echo_Suppression(POSIX_Echo_Suppression&& other) = delete;
         POSIX_Echo_Suppression& operator=(const POSIX_Echo_Suppression& other) = delete;
         POSIX_Echo_Suppression& operator=(POSIX_Echo_Suppression&& other) = delete;

      private:
         int m_stdin_fd;
         struct termios m_old_termios;
   };

   return std::make_unique<POSIX_Echo_Suppression>();

#elif defined(BOTAN_TARGET_OS_HAS_WIN32)

   class Win32_Echo_Suppression final : public Echo_Suppression {
      public:
         Win32_Echo_Suppression() {
            m_input_handle = ::GetStdHandle(STD_INPUT_HANDLE);
            if(::GetConsoleMode(m_input_handle, &m_console_state) == 0)
               throw System_Error("Getting console mode failed", ::GetLastError());

            DWORD new_mode = ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT;
            if(::SetConsoleMode(m_input_handle, new_mode) == 0)
               throw System_Error("Setting console mode failed", ::GetLastError());
         }

         void reenable_echo() override {
            if(m_input_handle != INVALID_HANDLE_VALUE) {
               if(::SetConsoleMode(m_input_handle, m_console_state) == 0)
                  throw System_Error("Setting console mode failed", ::GetLastError());
               m_input_handle = INVALID_HANDLE_VALUE;
            }
         }

         ~Win32_Echo_Suppression() override {
            try {
               reenable_echo();
            } catch(...) {}
         }

         Win32_Echo_Suppression(const Win32_Echo_Suppression& other) = delete;
         Win32_Echo_Suppression(Win32_Echo_Suppression&& other) = delete;
         Win32_Echo_Suppression& operator=(const Win32_Echo_Suppression& other) = delete;
         Win32_Echo_Suppression& operator=(Win32_Echo_Suppression&& other) = delete;

      private:
         HANDLE m_input_handle;
         DWORD m_console_state;
   };

   return std::make_unique<Win32_Echo_Suppression>();

#else

   // Not supported on this platform, return null
   return nullptr;
#endif
}

}  // namespace Botan
/*
* PBKDF
* (C) 2012 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_PBKDF2)
#endif

#if defined(BOTAN_HAS_PGP_S2K)
#endif

namespace Botan {

std::unique_ptr<PBKDF> PBKDF::create(std::string_view algo_spec, std::string_view provider) {
   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_PBKDF2)
   if(req.algo_name() == "PBKDF2") {
      if(provider.empty() || provider == "base") {
         if(auto mac = MessageAuthenticationCode::create("HMAC(" + req.arg(0) + ")")) {
            return std::make_unique<PKCS5_PBKDF2>(std::move(mac));
         }

         if(auto mac = MessageAuthenticationCode::create(req.arg(0))) {
            return std::make_unique<PKCS5_PBKDF2>(std::move(mac));
         }
      }

      return nullptr;
   }
#endif

#if defined(BOTAN_HAS_PGP_S2K)
   if(req.algo_name() == "OpenPGP-S2K" && req.arg_count() == 1) {
      if(auto hash = HashFunction::create(req.arg(0))) {
         return std::make_unique<OpenPGP_S2K>(std::move(hash));
      }
   }
#endif

   BOTAN_UNUSED(req, provider);

   return nullptr;
}

//static
std::unique_ptr<PBKDF> PBKDF::create_or_throw(std::string_view algo, std::string_view provider) {
   if(auto pbkdf = PBKDF::create(algo, provider)) {
      return pbkdf;
   }
   throw Lookup_Error("PBKDF", algo, provider);
}

std::vector<std::string> PBKDF::providers(std::string_view algo_spec) {
   return probe_providers_of<PBKDF>(algo_spec);
}

void PBKDF::pbkdf_timed(uint8_t out[],
                        size_t out_len,
                        std::string_view passphrase,
                        const uint8_t salt[],
                        size_t salt_len,
                        std::chrono::milliseconds msec,
                        size_t& iterations) const {
   iterations = pbkdf(out, out_len, passphrase, salt, salt_len, 0, msec);
}

void PBKDF::pbkdf_iterations(uint8_t out[],
                             size_t out_len,
                             std::string_view passphrase,
                             const uint8_t salt[],
                             size_t salt_len,
                             size_t iterations) const {
   if(iterations == 0) {
      throw Invalid_Argument(name() + ": Invalid iteration count");
   }

   const size_t iterations_run =
      pbkdf(out, out_len, passphrase, salt, salt_len, iterations, std::chrono::milliseconds(0));
   BOTAN_ASSERT_EQUAL(iterations, iterations_run, "Expected PBKDF iterations");
}

secure_vector<uint8_t> PBKDF::pbkdf_iterations(
   size_t out_len, std::string_view passphrase, const uint8_t salt[], size_t salt_len, size_t iterations) const {
   secure_vector<uint8_t> out(out_len);
   pbkdf_iterations(out.data(), out_len, passphrase, salt, salt_len, iterations);
   return out;
}

secure_vector<uint8_t> PBKDF::pbkdf_timed(size_t out_len,
                                          std::string_view passphrase,
                                          const uint8_t salt[],
                                          size_t salt_len,
                                          std::chrono::milliseconds msec,
                                          size_t& iterations) const {
   secure_vector<uint8_t> out(out_len);
   pbkdf_timed(out.data(), out_len, passphrase, salt, salt_len, msec, iterations);
   return out;
}

}  // namespace Botan
/*
* (C) 2018 Ribose Inc
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_PBKDF2)
#endif

#if defined(BOTAN_HAS_PGP_S2K)
#endif

#if defined(BOTAN_HAS_SCRYPT)
#endif

#if defined(BOTAN_HAS_ARGON2)
#endif

#if defined(BOTAN_HAS_PBKDF_BCRYPT)
#endif

#if defined(BOTAN_HAS_PKCS12_KDF)
#endif

namespace Botan {

void PasswordHash::derive_key(uint8_t out[],
                              size_t out_len,
                              const char* password,
                              size_t password_len,
                              const uint8_t salt[],
                              size_t salt_len,
                              const uint8_t ad[],
                              size_t ad_len,
                              const uint8_t key[],
                              size_t key_len) const {
   BOTAN_UNUSED(ad, key);

   if(ad_len == 0 && key_len == 0) {
      return this->derive_key(out, out_len, password, password_len, salt, salt_len);
   } else {
      throw Not_Implemented("PasswordHash " + this->to_string() + " does not support AD or key");
   }
}

std::unique_ptr<PasswordHashFamily> PasswordHashFamily::create(std::string_view algo_spec, std::string_view provider) {
   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_PBKDF2)
   if(req.algo_name() == "PBKDF2") {
      if(provider.empty() || provider == "base") {
         if(auto mac = MessageAuthenticationCode::create("HMAC(" + req.arg(0) + ")")) {
            return std::make_unique<PBKDF2_Family>(std::move(mac));
         }

         if(auto mac = MessageAuthenticationCode::create(req.arg(0))) {
            return std::make_unique<PBKDF2_Family>(std::move(mac));
         }
      }

      return nullptr;
   }
#endif

#if defined(BOTAN_HAS_SCRYPT)
   if(req.algo_name() == "Scrypt") {
      return std::make_unique<Scrypt_Family>();
   }
#endif

#if defined(BOTAN_HAS_ARGON2)
   if(req.algo_name() == "Argon2d") {
      return std::make_unique<Argon2_Family>(static_cast<uint8_t>(0));
   } else if(req.algo_name() == "Argon2i") {
      return std::make_unique<Argon2_Family>(static_cast<uint8_t>(1));
   } else if(req.algo_name() == "Argon2id") {
      return std::make_unique<Argon2_Family>(static_cast<uint8_t>(2));
   }
#endif

#if defined(BOTAN_HAS_PBKDF_BCRYPT)
   if(req.algo_name() == "Bcrypt-PBKDF") {
      return std::make_unique<Bcrypt_PBKDF_Family>();
   }
#endif

#if defined(BOTAN_HAS_PGP_S2K)
   if(req.algo_name() == "OpenPGP-S2K" && req.arg_count() == 1) {
      if(auto hash = HashFunction::create(req.arg(0))) {
         return std::make_unique<RFC4880_S2K_Family>(std::move(hash));
      }
   }
#endif

#if defined(BOTAN_HAS_PKCS12_KDF)
   if(req.algo_name() == "PKCS12-KDF" && req.arg_count() == 2) {
      if(auto hash = HashFunction::create(req.arg(0))) {
         const auto id_param = req.arg_as_integer(1);
         return std::make_unique<PKCS12_KDF_Family>(std::move(hash), id_param);
      }
   }
#endif

   BOTAN_UNUSED(req);
   BOTAN_UNUSED(provider);

   return nullptr;
}

//static
std::unique_ptr<PasswordHashFamily> PasswordHashFamily::create_or_throw(std::string_view algo,
                                                                        std::string_view provider) {
   if(auto pbkdf = PasswordHashFamily::create(algo, provider)) {
      return pbkdf;
   }
   throw Lookup_Error("PasswordHashFamily", algo, provider);
}

std::vector<std::string> PasswordHashFamily::providers(std::string_view algo_spec) {
   return probe_providers_of<PasswordHashFamily>(algo_spec);
}

}  // namespace Botan
/*
* PBKDF2
* (C) 1999-2007 Jack Lloyd
* (C) 2018 Ribose Inc
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

void pbkdf2_set_key(MessageAuthenticationCode& prf, const char* password, size_t password_len) {
   try {
      prf.set_key(as_span_of_bytes(password, password_len));
   } catch(Invalid_Key_Length&) {
      throw Invalid_Argument("PBKDF2 cannot accept passphrase of the given size");
   }
}

size_t tune_pbkdf2(MessageAuthenticationCode& prf,
                   size_t output_length,
                   uint64_t desired_msec,
                   uint64_t tuning_msec = 10) {
   if(output_length == 0) {
      output_length = 1;
   }

   const size_t prf_sz = prf.output_length();
   BOTAN_ASSERT_NOMSG(prf_sz > 0);
   const secure_vector<uint8_t> U(prf_sz);

   const size_t trial_iterations = 2000;

   // Short output ensures we only need a single PBKDF2 block

   prf.set_key(nullptr, 0);

   const uint64_t duration_nsec = measure_cost(tuning_msec, [&]() {
      uint8_t out[12] = {0};
      uint8_t salt[12] = {0};
      pbkdf2(prf, out, sizeof(out), salt, sizeof(salt), trial_iterations);
   });

   const uint64_t desired_nsec = desired_msec * 1000000;

   if(duration_nsec > desired_nsec) {
      return trial_iterations;
   }

   const size_t blocks_needed = (output_length + prf_sz - 1) / prf_sz;

   const size_t multiplier = static_cast<size_t>(desired_nsec / duration_nsec / blocks_needed);

   if(multiplier == 0) {
      return trial_iterations;
   } else {
      return trial_iterations * multiplier;
   }
}

}  // namespace

size_t pbkdf2(MessageAuthenticationCode& prf,
              uint8_t out[],
              size_t out_len,
              std::string_view password,
              const uint8_t salt[],
              size_t salt_len,
              size_t iterations,
              std::chrono::milliseconds msec) {
   if(iterations == 0) {
      iterations = tune_pbkdf2(prf, out_len, msec.count());
   }

   const PBKDF2 pbkdf2(prf, iterations);

   pbkdf2.derive_key(out, out_len, password.data(), password.size(), salt, salt_len);

   return iterations;
}

void pbkdf2(MessageAuthenticationCode& prf,
            uint8_t out[],
            size_t out_len,
            const uint8_t salt[],
            size_t salt_len,
            size_t iterations) {
   if(iterations == 0) {
      throw Invalid_Argument("PBKDF2: Invalid iteration count");
   }

   clear_mem(out, out_len);

   if(out_len == 0) {
      return;
   }

   const size_t prf_sz = prf.output_length();
   BOTAN_ASSERT_NOMSG(prf_sz > 0);

   // RFC 2898 Section 5.2: derived key length limited to (2^32 - 1) * hLen
   const auto blocks_required = ceil_division<uint64_t>(out_len, prf_sz);
   BOTAN_ARG_CHECK(blocks_required <= 0xFFFFFFFE, "PBKDF2 maximum output length exceeded");

   secure_vector<uint8_t> U(prf_sz);

   uint32_t counter = 1;
   while(out_len > 0) {
      const size_t prf_output = std::min<size_t>(prf_sz, out_len);

      prf.update(salt, salt_len);
      prf.update_be(counter++);
      prf.final(U.data());

      xor_buf(out, U.data(), prf_output);

      for(size_t i = 1; i != iterations; ++i) {
         prf.update(U);
         prf.final(U.data());
         xor_buf(out, U.data(), prf_output);
      }

      out_len -= prf_output;
      out += prf_output;
   }
}

// PBKDF interface
size_t PKCS5_PBKDF2::pbkdf(uint8_t key[],
                           size_t key_len,
                           std::string_view password,
                           const uint8_t salt[],
                           size_t salt_len,
                           size_t iterations,
                           std::chrono::milliseconds msec) const {
   if(iterations == 0) {
      iterations = tune_pbkdf2(*m_mac, key_len, msec.count());
   }

   const PBKDF2 pbkdf2(*m_mac, iterations);

   pbkdf2.derive_key(key, key_len, password.data(), password.size(), salt, salt_len);

   return iterations;
}

std::string PKCS5_PBKDF2::name() const {
   return fmt("PBKDF2({})", m_mac->name());
}

std::unique_ptr<PBKDF> PKCS5_PBKDF2::new_object() const {
   return std::make_unique<PKCS5_PBKDF2>(m_mac->new_object());
}

// PasswordHash interface

PBKDF2::PBKDF2(const MessageAuthenticationCode& prf, size_t olen, std::chrono::milliseconds msec) :
      m_prf(prf.new_object()), m_iterations(tune_pbkdf2(*m_prf, olen, msec.count())) {}

std::string PBKDF2::to_string() const {
   return fmt("PBKDF2({},{})", m_prf->name(), m_iterations);
}

void PBKDF2::derive_key(uint8_t out[],
                        size_t out_len,
                        const char* password,
                        const size_t password_len,
                        const uint8_t salt[],
                        size_t salt_len) const {
   pbkdf2_set_key(*m_prf, password, password_len);
   pbkdf2(*m_prf, out, out_len, salt, salt_len, m_iterations);
}

std::string PBKDF2_Family::name() const {
   return fmt("PBKDF2({})", m_prf->name());
}

std::unique_ptr<PasswordHash> PBKDF2_Family::tune_params(size_t output_len,
                                                         uint64_t desired_runtime_msec,
                                                         std::optional<size_t> /*max_memory*/,
                                                         uint64_t tune_msec) const {
   auto iterations = tune_pbkdf2(*m_prf, output_len, desired_runtime_msec, tune_msec);
   return std::make_unique<PBKDF2>(*m_prf, iterations);
}

std::unique_ptr<PasswordHash> PBKDF2_Family::default_params() const {
   return std::make_unique<PBKDF2>(*m_prf, 150000);
}

std::unique_ptr<PasswordHash> PBKDF2_Family::from_params(size_t iter, size_t /*i2*/, size_t /*i3*/) const {
   return std::make_unique<PBKDF2>(*m_prf, iter);
}

std::unique_ptr<PasswordHash> PBKDF2_Family::from_iterations(size_t iter) const {
   return std::make_unique<PBKDF2>(*m_prf, iter);
}

}  // namespace Botan
/*
* Derived from poly1305-donna-64.h by Andrew Moon <liquidsun@gmail.com>
* in https://github.com/floodyberry/poly1305-donna
*
* (C) 2014 Andrew Moon
* (C) 2014,2025,2026 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_POLY1305_AVX2) || defined(BOTAN_HAS_POLY1305_AVX512)
#endif

namespace Botan {

namespace {

// State layout: pad || accum || r || r^2 || r^3 || ... || r^n
// This ordering allows extending with more powers of r at the end
constexpr size_t PAD_BASE = 0;  // pad[0..1]
constexpr size_t H_BASE = 2;    // h[0..2] (accumulator)
constexpr size_t R_BASE = 5;    // r^1[0..2], r^2[3..5], r^3[6..8], etc.

// Multiply two values in radix 2^44 representation mod (2^130 - 5)
// h = a * b mod p
BOTAN_FORCE_INLINE void poly1305_mul_44(uint64_t& h0,
                                        uint64_t& h1,
                                        uint64_t& h2,
                                        uint64_t a0,
                                        uint64_t a1,
                                        uint64_t a2,
                                        uint64_t b0,
                                        uint64_t b1,
                                        uint64_t b2) {
   constexpr uint64_t M44 = 0xFFFFFFFFFFF;
   constexpr uint64_t M42 = 0x3FFFFFFFFFF;

#if !defined(BOTAN_TARGET_HAS_NATIVE_UINT128)
   typedef donna128 uint128_t;
#endif

   const uint64_t s1 = b1 * 20;
   const uint64_t s2 = b2 * 20;

   const uint128_t d0 = uint128_t(a0) * b0 + uint128_t(a1) * s2 + uint128_t(a2) * s1;
   const uint64_t c0 = carry_shift(d0, 44);

   const uint128_t d1 = uint128_t(a0) * b1 + uint128_t(a1) * b0 + uint128_t(a2) * s2 + c0;
   const uint64_t c1 = carry_shift(d1, 44);

   const uint128_t d2 = uint128_t(a0) * b2 + uint128_t(a1) * b1 + uint128_t(a2) * b0 + c1;
   const uint64_t c2 = carry_shift(d2, 42);

   h0 = (d0 & M44) + c2 * 5;
   h1 = (d1 & M44) + (h0 >> 44);
   h0 &= M44;
   h2 = d2 & M42;
}

// Extend powers of r from current max to target
void poly1305_extend_powers(secure_vector<uint64_t>& X, size_t target_powers) {
   const size_t current_powers = (X.size() - 5) / 3;

   if(current_powers >= target_powers) {
      return;
   }

   // Load r^1 for multiplication
   const uint64_t r0 = X[R_BASE + 0];
   const uint64_t r1 = X[R_BASE + 1];
   const uint64_t r2 = X[R_BASE + 2];

   X.resize(5 + target_powers * 3);

   // Compute r^(current+1) through r^target
   for(size_t i = current_powers + 1; i <= target_powers; ++i) {
      const size_t offset = R_BASE + (i - 1) * 3;
      poly1305_mul_44(
         X[offset + 0], X[offset + 1], X[offset + 2], X[offset - 3], X[offset - 2], X[offset - 1], r0, r1, r2);
   }
}

// Initialize Poly1305 state and precompute powers of r
void poly1305_init(secure_vector<uint64_t>& X, const uint8_t key[32]) {
   X.clear();
   X.reserve(2 + 3 + 2 * 3);
   X.resize(2 + 3 + 3);

   /* Save pad for later (first 2 slots) */
   X[PAD_BASE + 0] = load_le<uint64_t>(key, 2);
   X[PAD_BASE + 1] = load_le<uint64_t>(key, 3);

   /* h = 0 (accumulator, next 3 slots) */
   X[H_BASE + 0] = 0;
   X[H_BASE + 1] = 0;
   X[H_BASE + 2] = 0;

   /* r &= 0xffffffc0ffffffc0ffffffc0fffffff (clamping) */
   const uint64_t t0 = load_le<uint64_t>(key, 0);
   const uint64_t t1 = load_le<uint64_t>(key, 1);

   const uint64_t r0 = (t0) & 0xffc0fffffff;
   const uint64_t r1 = ((t0 >> 44) | (t1 << 20)) & 0xfffffc0ffff;
   const uint64_t r2 = ((t1 >> 24)) & 0x00ffffffc0f;

   // Store r^1
   X[R_BASE + 0] = r0;
   X[R_BASE + 1] = r1;
   X[R_BASE + 2] = r2;

   poly1305_extend_powers(X, 2);
}

// Process a single block: h = (h + m) * r mod p
BOTAN_FORCE_INLINE void poly1305_block_single(uint64_t& h0,
                                              uint64_t& h1,
                                              uint64_t& h2,
                                              uint64_t r0,
                                              uint64_t r1,
                                              uint64_t r2,
                                              uint64_t s1,
                                              uint64_t s2,
                                              const uint8_t* m,
                                              uint64_t hibit) {
   constexpr uint64_t M44 = 0xFFFFFFFFFFF;
   constexpr uint64_t M42 = 0x3FFFFFFFFFF;

#if !defined(BOTAN_TARGET_HAS_NATIVE_UINT128)
   typedef donna128 uint128_t;
#endif

   const uint64_t t0 = load_le<uint64_t>(m, 0);
   const uint64_t t1 = load_le<uint64_t>(m, 1);

   h0 += (t0 & M44);
   h1 += ((t0 >> 44) | (t1 << 20)) & M44;
   h2 += ((t1 >> 24) & M42) | hibit;

   const uint128_t d0 = uint128_t(h0) * r0 + uint128_t(h1) * s2 + uint128_t(h2) * s1;
   const uint64_t c0 = carry_shift(d0, 44);

   const uint128_t d1 = uint128_t(h0) * r1 + uint128_t(h1) * r0 + uint128_t(h2) * s2 + c0;
   const uint64_t c1 = carry_shift(d1, 44);

   const uint128_t d2 = uint128_t(h0) * r2 + uint128_t(h1) * r1 + uint128_t(h2) * r0 + c1;
   const uint64_t c2 = carry_shift(d2, 42);

   h0 = (d0 & M44) + c2 * 5;
   h1 = (d1 & M44) + (h0 >> 44);
   h0 &= M44;
   h2 = d2 & M42;
}

// Process two blocks in parallel: h = ((h + m0) * r + m1) * r = (h + m0) * r^2 + m1 * r
// The multiplications by r^2 and r are independent, enabling ILP
BOTAN_FORCE_INLINE void poly1305_block_pair(uint64_t& h0,
                                            uint64_t& h1,
                                            uint64_t& h2,
                                            uint64_t r0,
                                            uint64_t r1,
                                            uint64_t r2,
                                            uint64_t s1,
                                            uint64_t s2,
                                            uint64_t rr0,
                                            uint64_t rr1,
                                            uint64_t rr2,
                                            uint64_t ss1,
                                            uint64_t ss2,
                                            const uint8_t* m,
                                            uint64_t hibit) {
   constexpr uint64_t M44 = 0xFFFFFFFFFFF;
   constexpr uint64_t M42 = 0x3FFFFFFFFFF;

#if !defined(BOTAN_TARGET_HAS_NATIVE_UINT128)
   typedef donna128 uint128_t;
#endif

   // Load first block (will be multiplied by r^2)
   const uint64_t m0_t0 = load_le<uint64_t>(m, 0);
   const uint64_t m0_t1 = load_le<uint64_t>(m, 1);

   // Load second block (will be multiplied by r)
   const uint64_t m1_t0 = load_le<uint64_t>(m + 16, 0);
   const uint64_t m1_t1 = load_le<uint64_t>(m + 16, 1);

   // Add first block to h
   h0 += (m0_t0 & M44);
   h1 += ((m0_t0 >> 44) | (m0_t1 << 20)) & M44;
   h2 += ((m0_t1 >> 24) & M42) | hibit;

   // Convert second block to limbs
   const uint64_t b0 = (m1_t0 & M44);
   const uint64_t b1 = ((m1_t0 >> 44) | (m1_t1 << 20)) & M44;
   const uint64_t b2 = ((m1_t1 >> 24) & M42) | hibit;

   // Compute (h + m0) * r^2 + m1 * r
   const uint128_t d0 = uint128_t(h0) * rr0 + uint128_t(h1) * ss2 + uint128_t(h2) * ss1 + uint128_t(b0) * r0 +
                        uint128_t(b1) * s2 + uint128_t(b2) * s1;
   const uint64_t c0 = carry_shift(d0, 44);

   const uint128_t d1 = uint128_t(h0) * rr1 + uint128_t(h1) * rr0 + uint128_t(h2) * ss2 + uint128_t(b0) * r1 +
                        uint128_t(b1) * r0 + uint128_t(b2) * s2 + c0;
   const uint64_t c1 = carry_shift(d1, 44);

   const uint128_t d2 = uint128_t(h0) * rr2 + uint128_t(h1) * rr1 + uint128_t(h2) * rr0 + uint128_t(b0) * r2 +
                        uint128_t(b1) * r1 + uint128_t(b2) * r0 + c1;
   const uint64_t c2 = carry_shift(d2, 42);

   h0 = (d0 & M44) + c2 * 5;
   h1 = (d1 & M44) + (h0 >> 44);
   h0 &= M44;
   h2 = d2 & M42;
}

void poly1305_blocks(secure_vector<uint64_t>& X, const uint8_t* m, size_t blocks, bool is_final = false) {
   const uint64_t hibit = is_final ? 0 : (static_cast<uint64_t>(1) << 40);

   // Load r (at R_BASE + 0)
   const uint64_t r0 = X[R_BASE + 0];
   const uint64_t r1 = X[R_BASE + 1];
   const uint64_t r2 = X[R_BASE + 2];
   const uint64_t s1 = r1 * 20;
   const uint64_t s2 = r2 * 20;

   // Load r^2 (at R_BASE + 3)
   const uint64_t rr0 = X[R_BASE + 3];
   const uint64_t rr1 = X[R_BASE + 4];
   const uint64_t rr2 = X[R_BASE + 5];

   // Precompute
   const uint64_t ss1 = rr1 * 20;
   const uint64_t ss2 = rr2 * 20;

   // Load accumulator
   uint64_t h0 = X[H_BASE + 0];
   uint64_t h1 = X[H_BASE + 1];
   uint64_t h2 = X[H_BASE + 2];

   while(blocks >= 2) {
      poly1305_block_pair(h0, h1, h2, r0, r1, r2, s1, s2, rr0, rr1, rr2, ss1, ss2, m, hibit);
      m += 32;
      blocks -= 2;
   }

   // Final block?
   if(blocks > 0) {
      poly1305_block_single(h0, h1, h2, r0, r1, r2, s1, s2, m, hibit);
   }

   // Store accumulator
   X[H_BASE + 0] = h0;
   X[H_BASE + 1] = h1;
   X[H_BASE + 2] = h2;
}

void poly1305_finish(secure_vector<uint64_t>& X, uint8_t mac[16]) {
   constexpr uint64_t M44 = 0xFFFFFFFFFFF;
   constexpr uint64_t M42 = 0x3FFFFFFFFFF;

   /* fully carry h */
   uint64_t h0 = X[H_BASE + 0];
   uint64_t h1 = X[H_BASE + 1];
   uint64_t h2 = X[H_BASE + 2];

   uint64_t c = (h1 >> 44);
   h1 &= M44;
   h2 += c;
   c = (h2 >> 42);
   h2 &= M42;
   h0 += c * 5;
   c = (h0 >> 44);
   h0 &= M44;
   h1 += c;
   c = (h1 >> 44);
   h1 &= M44;
   h2 += c;
   c = (h2 >> 42);
   h2 &= M42;
   h0 += c * 5;
   c = (h0 >> 44);
   h0 &= M44;
   h1 += c;

   /* compute h + -p */
   uint64_t g0 = h0 + 5;
   c = (g0 >> 44);
   g0 &= M44;
   uint64_t g1 = h1 + c;
   c = (g1 >> 44);
   g1 &= M44;
   const uint64_t g2 = h2 + c - (static_cast<uint64_t>(1) << 42);

   /* select h if h < p, or h + -p if h >= p */
   const auto h_mask = CT::Mask<uint64_t>::expand_top_bit(g2);
   h0 = h_mask.select(h0, g0);
   h1 = h_mask.select(h1, g1);
   h2 = h_mask.select(h2, g2);

   /* h = (h + pad) */
   const uint64_t t0 = X[PAD_BASE + 0];
   const uint64_t t1 = X[PAD_BASE + 1];

   h0 += ((t0)&M44);
   c = (h0 >> 44);
   h0 &= M44;
   h1 += (((t0 >> 44) | (t1 << 20)) & M44) + c;
   c = (h1 >> 44);
   h1 &= M44;
   h2 += (((t1 >> 24)) & M42) + c;
   h2 &= M42;

   /* mac = h % (2^128) */
   h0 = ((h0) | (h1 << 44));
   h1 = ((h1 >> 20) | (h2 << 24));

   store_le(mac, h0, h1);

   /* zero out the state */
   clear_mem(X.data(), X.size());
}

}  // namespace

void Poly1305::clear() {
   zap(m_poly);
   m_buffer.clear();
}

bool Poly1305::has_keying_material() const {
   // Minimum size: pad(2) + accum(3) + r(3) + r^2(3) = 11
   return m_poly.size() >= 11;
}

void Poly1305::start_msg(std::span<const uint8_t> nonce) {
   if(!nonce.empty()) {
      throw Invalid_IV_Length(name(), nonce.size());
   }
   assert_key_material_set();

   m_buffer.clear();
   m_poly[H_BASE + 0] = 0;
   m_poly[H_BASE + 1] = 0;
   m_poly[H_BASE + 2] = 0;
}

void Poly1305::key_schedule(std::span<const uint8_t> key) {
   m_buffer.clear();

   poly1305_init(m_poly, key.data());
}

std::string Poly1305::provider() const {
#if defined(BOTAN_HAS_POLY1305_AVX512)
   if(auto feat = CPUID::check(CPUID::Feature::AVX512)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_POLY1305_AVX2)
   if(auto feat = CPUID::check(CPUID::Feature::AVX2)) {
      return *feat;
   }
#endif

   return "base";
}

void Poly1305::add_data(std::span<const uint8_t> input) {
   assert_key_material_set();

   BufferSlicer in(input);

   while(!in.empty()) {
      if(const auto one_block = m_buffer.handle_unaligned_data(in)) {
         poly1305_blocks(m_poly, one_block->data(), 1);
      }

      if(m_buffer.in_alignment()) {
         const auto [aligned_data, full_blocks] = m_buffer.aligned_data_to_process(in);
         if(full_blocks > 0) {
            const uint8_t* data_ptr = aligned_data.data();
            size_t blocks_remaining = full_blocks;

#if defined(BOTAN_HAS_POLY1305_AVX512)
            if(blocks_remaining >= 8 * 3 && CPUID::has(CPUID::Feature::AVX512)) {
               // Lazily compute r^3 through r^8 on first AVX512 use
               poly1305_extend_powers(m_poly, 8);
               const size_t processed = poly1305_avx512_blocks(m_poly, data_ptr, blocks_remaining);
               data_ptr += processed * 16;
               blocks_remaining -= processed;
            }
#endif

#if defined(BOTAN_HAS_POLY1305_AVX2)
            if(blocks_remaining >= 4 * 6 && CPUID::has(CPUID::Feature::AVX2)) {
               // Lazily compute r^3 and r^4 on first AVX2 use
               poly1305_extend_powers(m_poly, 4);
               const size_t processed = poly1305_avx2_blocks(m_poly, data_ptr, blocks_remaining);
               data_ptr += processed * 16;
               blocks_remaining -= processed;
            }
#endif

            if(blocks_remaining > 0) {
               poly1305_blocks(m_poly, data_ptr, blocks_remaining);
            }
         }
      }
   }
}

void Poly1305::final_result(std::span<uint8_t> out) {
   assert_key_material_set();

   if(!m_buffer.in_alignment()) {
      const uint8_t final_byte = 0x01;
      m_buffer.append({&final_byte, 1});
      m_buffer.fill_up_with_zeros();
      poly1305_blocks(m_poly, m_buffer.consume().data(), 1, true);
   }

   poly1305_finish(m_poly, out.data());

   m_poly.clear();
   m_buffer.clear();
}

}  // namespace Botan
/*
* AES Key Wrap (RFC 3394)
* (C) 2011 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

secure_vector<uint8_t> rfc3394_keywrap(const secure_vector<uint8_t>& key, const SymmetricKey& kek) {
   BOTAN_ARG_CHECK(kek.size() == 16 || kek.size() == 24 || kek.size() == 32, "Invalid KEK length for NIST key wrap");

   const std::string cipher_name = "AES-" + std::to_string(8 * kek.size());
   auto aes = BlockCipher::create_or_throw(cipher_name);
   aes->set_key(kek);

   std::vector<uint8_t> wrapped = nist_key_wrap(key.data(), key.size(), *aes);
   return secure_vector<uint8_t>(wrapped.begin(), wrapped.end());
}

secure_vector<uint8_t> rfc3394_keyunwrap(const secure_vector<uint8_t>& key, const SymmetricKey& kek) {
   BOTAN_ARG_CHECK(kek.size() == 16 || kek.size() == 24 || kek.size() == 32, "Invalid KEK length for NIST key wrap");

   BOTAN_ARG_CHECK(key.size() >= 16 && key.size() % 8 == 0, "Bad input key size for NIST key unwrap");

   const std::string cipher_name = "AES-" + std::to_string(8 * kek.size());
   auto aes = BlockCipher::create_or_throw(cipher_name);
   aes->set_key(kek);

   return nist_key_unwrap(key.data(), key.size(), *aes);
}

}  // namespace Botan
/*
* (C) 2016 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_ENTROPY_SOURCE)
#endif

#if defined(BOTAN_HAS_SYSTEM_RNG)
#elif defined(BOTAN_HAS_OS_UTILS)
#endif


namespace Botan {

void RandomNumberGenerator::randomize_with_ts_input(std::span<uint8_t> output) {
   if(this->accepts_input()) {
      std::array<uint8_t, 16> additional_input = {0};

#if defined(BOTAN_HAS_SYSTEM_RNG)
      // If we have a system RNG just read 128 bits from that
      system_rng().randomize(additional_input);
      constexpr size_t written = additional_input.size();
#elif defined(BOTAN_HAS_OS_UTILS)
      // Otherwise take clock + pid
      const uint64_t clock = OS::get_high_resolution_clock();
      const uint32_t pid = OS::get_process_id();  // 0 if no PIDs on this system

      store_le(std::span{additional_input}.first<8>(), clock);
      store_le(std::span{additional_input}.subspan<8, 4>(), pid);
      const size_t written = 8 + (pid != 0) ? 4 : 0;
#else
      // Nothing to use in this case
      constexpr size_t written = 0;
#endif

      this->fill_bytes_with_input(output, std::span{additional_input}.first(written));
   } else {
      this->fill_bytes_with_input(output, {});
   }
}

size_t RandomNumberGenerator::reseed_from_sources(Entropy_Sources& srcs, size_t poll_bits) {
   if(this->accepts_input()) {
#if defined(BOTAN_HAS_ENTROPY_SOURCE)
      return srcs.poll(*this, poll_bits);
#else
      BOTAN_UNUSED(srcs, poll_bits);
#endif
   }

   return 0;
}

void RandomNumberGenerator::reseed_from_rng(RandomNumberGenerator& rng, size_t poll_bits) {
   if(this->accepts_input()) {
      this->add_entropy(rng.random_vec(poll_bits / 8));
   }
}

void Null_RNG::fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) {
   // throw if caller tries to obtain random bytes
   if(!output.empty()) {
      throw PRNG_Unseeded("Null_RNG called");
   }
}

}  // namespace Botan
/*
* SHA-{224,256}
* (C) 1999-2010,2017 Jack Lloyd
*     2007 FlexSecure GmbH
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

namespace Botan {

namespace {

std::string sha256_provider() {
#if defined(BOTAN_HAS_SHA2_32_ARMV8)
   if(auto feat = CPUID::check(CPUID::Feature::SHA2)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_X86)
   if(auto feat = CPUID::check(CPUID::Feature::SHA)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_X86_AVX2)
   if(auto feat = CPUID::check(CPUID::Feature::AVX2, CPUID::Feature::BMI)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_SIMD)
   if(auto feat = CPUID::check(CPUID::Feature::SIMD_4X32)) {
      return *feat;
   }
#endif

   return "base";
}

}  // namespace

/*
* SHA-224 / SHA-256 compression function
*/
void BOTAN_SCRUB_STACK_AFTER_RETURN SHA_256::compress_digest(digest_type& digest,
                                                             std::span<const uint8_t> input,
                                                             size_t blocks) {
#if defined(BOTAN_HAS_SHA2_32_X86)
   if(CPUID::has(CPUID::Feature::SHA)) {
      return SHA_256::compress_digest_x86(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_ARMV8)
   if(CPUID::has(CPUID::Feature::SHA2)) {
      return SHA_256::compress_digest_armv8(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_X86_AVX2)
   if(CPUID::has(CPUID::Feature::AVX2, CPUID::Feature::BMI)) {
      return SHA_256::compress_digest_x86_avx2(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_32_SIMD)
   if(CPUID::has(CPUID::Feature::SIMD_4X32)) {
      return SHA_256::compress_digest_x86_simd(digest, input, blocks);
   }
#endif

   uint32_t A = digest[0];
   uint32_t B = digest[1];
   uint32_t C = digest[2];
   uint32_t D = digest[3];
   uint32_t E = digest[4];
   uint32_t F = digest[5];
   uint32_t G = digest[6];
   uint32_t H = digest[7];

   std::array<uint32_t, 16> W{};

   BufferSlicer in(input);

   for(size_t i = 0; i != blocks; ++i) {
      load_be(W, in.take<block_bytes>());

      // clang-format off

      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x428A2F98);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x71374491);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0xB5C0FBCF);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0xE9B5DBA5);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x3956C25B);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x59F111F1);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x923F82A4);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0xAB1C5ED5);
      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0xD807AA98);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0x12835B01);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0x243185BE);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0x550C7DC3);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0x72BE5D74);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0x80DEB1FE);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0x9BDC06A7);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0xC19BF174);

      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0xE49B69C1);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0xEFBE4786);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x0FC19DC6);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x240CA1CC);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x2DE92C6F);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x4A7484AA);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x5CB0A9DC);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x76F988DA);
      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0x983E5152);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0xA831C66D);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0xB00327C8);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0xBF597FC7);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0xC6E00BF3);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xD5A79147);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0x06CA6351);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0x14292967);

      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x27B70A85);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x2E1B2138);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x4D2C6DFC);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x53380D13);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x650A7354);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x766A0ABB);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x81C2C92E);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x92722C85);
      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0xA2BFE8A1);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0xA81A664B);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0xC24B8B70);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0xC76C51A3);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0xD192E819);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xD6990624);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0xF40E3585);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0x106AA070);

      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x19A4C116);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x1E376C08);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x2748774C);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x34B0BCB5);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x391C0CB3);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x4ED8AA4A);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x5B9CCA4F);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x682E6FF3);
      SHA2_32_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0x748F82EE);
      SHA2_32_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0x78A5636F);
      SHA2_32_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0x84C87814);
      SHA2_32_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0x8CC70208);
      SHA2_32_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0x90BEFFFA);
      SHA2_32_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xA4506CEB);
      SHA2_32_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0xBEF9A3F7);
      SHA2_32_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0xC67178F2);

      // clang-format on

      A = (digest[0] += A);
      B = (digest[1] += B);
      C = (digest[2] += C);
      D = (digest[3] += D);
      E = (digest[4] += E);
      F = (digest[5] += F);
      G = (digest[6] += G);
      H = (digest[7] += H);
   }
}

std::string SHA_224::provider() const {
   return sha256_provider();
}

void SHA_224::compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
   SHA_256::compress_digest(digest, input, blocks);
}

void SHA_224::init(digest_type& digest) {
   digest.assign({0xC1059ED8, 0x367CD507, 0x3070DD17, 0xF70E5939, 0xFFC00B31, 0x68581511, 0x64F98FA7, 0xBEFA4FA4});
}

std::unique_ptr<HashFunction> SHA_224::new_object() const {
   return std::make_unique<SHA_224>();
}

std::unique_ptr<HashFunction> SHA_224::copy_state() const {
   return std::make_unique<SHA_224>(*this);
}

void SHA_224::add_data(std::span<const uint8_t> input) {
   m_md.update(input);
}

void SHA_224::final_result(std::span<uint8_t> output) {
   m_md.final(output);
}

std::string SHA_256::provider() const {
   return sha256_provider();
}

void SHA_256::compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
   SHA_256::compress_digest(digest, input, blocks);
}

void SHA_256::init(digest_type& digest) {
   digest.assign({0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19});
}

std::unique_ptr<HashFunction> SHA_256::new_object() const {
   return std::make_unique<SHA_256>();
}

std::unique_ptr<HashFunction> SHA_256::copy_state() const {
   return std::make_unique<SHA_256>(*this);
}

void SHA_256::add_data(std::span<const uint8_t> input) {
   m_md.update(input);
}

void SHA_256::final_result(std::span<uint8_t> output) {
   m_md.final(output);
}

}  // namespace Botan
/*
* SHA-{384,512}
* (C) 1999-2011,2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CPUID)
#endif

namespace Botan {

namespace {

std::string sha512_provider() {
#if defined(BOTAN_HAS_SHA2_64_X86)
   if(auto feat = CPUID::check(CPUID::Feature::SHA512)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_ARMV8)
   if(auto feat = CPUID::check(CPUID::Feature::SHA2_512)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_X86_AVX512)
   if(auto feat = CPUID::check(CPUID::Feature::AVX512, CPUID::Feature::BMI)) {
      return *feat;
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_X86_AVX2)
   if(auto feat = CPUID::check(CPUID::Feature::AVX2, CPUID::Feature::BMI)) {
      return *feat;
   }
#endif

   return "base";
}

}  // namespace

/*
* SHA-{384,512} Compression Function
*/
//static
void SHA_512::compress_digest(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
#if defined(BOTAN_HAS_SHA2_64_X86)
   if(CPUID::has(CPUID::Feature::SHA512)) {
      return compress_digest_x86(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_ARMV8)
   if(CPUID::has(CPUID::Feature::SHA2_512)) {
      return compress_digest_armv8(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_X86_AVX512)
   if(CPUID::has(CPUID::Feature::AVX512, CPUID::Feature::BMI)) {
      return compress_digest_x86_avx512(digest, input, blocks);
   }
#endif

#if defined(BOTAN_HAS_SHA2_64_X86_AVX2)
   if(CPUID::has(CPUID::Feature::AVX2, CPUID::Feature::BMI)) {
      return compress_digest_x86_avx2(digest, input, blocks);
   }
#endif

   uint64_t A = digest[0];
   uint64_t B = digest[1];
   uint64_t C = digest[2];
   uint64_t D = digest[3];
   uint64_t E = digest[4];
   uint64_t F = digest[5];
   uint64_t G = digest[6];
   uint64_t H = digest[7];

   std::array<uint64_t, 16> W{};

   BufferSlicer in(input);

   for(size_t i = 0; i != blocks; ++i) {
      load_be(W, in.take<block_bytes>());

      // clang-format off

      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x428A2F98D728AE22);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x7137449123EF65CD);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0xB5C0FBCFEC4D3B2F);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0xE9B5DBA58189DBBC);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x3956C25BF348B538);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x59F111F1B605D019);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x923F82A4AF194F9B);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0xAB1C5ED5DA6D8118);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0xD807AA98A3030242);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0x12835B0145706FBE);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0x243185BE4EE4B28C);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0x550C7DC3D5FFB4E2);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0x72BE5D74F27B896F);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0x80DEB1FE3B1696B1);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0x9BDC06A725C71235);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0xC19BF174CF692694);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0xE49B69C19EF14AD2);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0xEFBE4786384F25E3);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x0FC19DC68B8CD5B5);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x240CA1CC77AC9C65);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x2DE92C6F592B0275);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x4A7484AA6EA6E483);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x5CB0A9DCBD41FBD4);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x76F988DA831153B5);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0x983E5152EE66DFAB);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0xA831C66D2DB43210);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0xB00327C898FB213F);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0xBF597FC7BEEF0EE4);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0xC6E00BF33DA88FC2);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xD5A79147930AA725);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0x06CA6351E003826F);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0x142929670A0E6E70);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x27B70A8546D22FFC);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x2E1B21385C26C926);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x4D2C6DFC5AC42AED);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x53380D139D95B3DF);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x650A73548BAF63DE);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x766A0ABB3C77B2A8);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x81C2C92E47EDAEE6);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x92722C851482353B);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0xA2BFE8A14CF10364);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0xA81A664BBC423001);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0xC24B8B70D0F89791);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0xC76C51A30654BE30);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0xD192E819D6EF5218);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xD69906245565A910);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0xF40E35855771202A);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0x106AA07032BBD1B8);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0x19A4C116B8D2D0C8);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0x1E376C085141AB53);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0x2748774CDF8EEB99);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0x34B0BCB5E19B48A8);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x391C0CB3C5C95A63);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x4ED8AA4AE3418ACB);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x5B9CCA4F7763E373);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x682E6FF3D6B2B8A3);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0x748F82EE5DEFB2FC);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0x78A5636F43172F60);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0x84C87814A1F0AB72);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0x8CC702081A6439EC);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0x90BEFFFA23631E28);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0xA4506CEBDE82BDE9);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0xBEF9A3F7B2C67915);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0xC67178F2E372532B);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 0], W[14], W[ 9], W[ 1], 0xCA273ECEEA26619C);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 1], W[15], W[10], W[ 2], 0xD186B8C721C0C207);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[ 2], W[ 0], W[11], W[ 3], 0xEADA7DD6CDE0EB1E);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[ 3], W[ 1], W[12], W[ 4], 0xF57D4F7FEE6ED178);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[ 4], W[ 2], W[13], W[ 5], 0x06F067AA72176FBA);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[ 5], W[ 3], W[14], W[ 6], 0x0A637DC5A2C898A6);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[ 6], W[ 4], W[15], W[ 7], 0x113F9804BEF90DAE);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[ 7], W[ 5], W[ 0], W[ 8], 0x1B710B35131C471B);
      SHA2_64_F(A, B, C, D, E, F, G, H, W[ 8], W[ 6], W[ 1], W[ 9], 0x28DB77F523047D84);
      SHA2_64_F(H, A, B, C, D, E, F, G, W[ 9], W[ 7], W[ 2], W[10], 0x32CAAB7B40C72493);
      SHA2_64_F(G, H, A, B, C, D, E, F, W[10], W[ 8], W[ 3], W[11], 0x3C9EBE0A15C9BEBC);
      SHA2_64_F(F, G, H, A, B, C, D, E, W[11], W[ 9], W[ 4], W[12], 0x431D67C49C100D4C);
      SHA2_64_F(E, F, G, H, A, B, C, D, W[12], W[10], W[ 5], W[13], 0x4CC5D4BECB3E42B6);
      SHA2_64_F(D, E, F, G, H, A, B, C, W[13], W[11], W[ 6], W[14], 0x597F299CFC657E2A);
      SHA2_64_F(C, D, E, F, G, H, A, B, W[14], W[12], W[ 7], W[15], 0x5FCB6FAB3AD6FAEC);
      SHA2_64_F(B, C, D, E, F, G, H, A, W[15], W[13], W[ 8], W[ 0], 0x6C44198C4A475817);

      // clang-format on

      A = (digest[0] += A);
      B = (digest[1] += B);
      C = (digest[2] += C);
      D = (digest[3] += D);
      E = (digest[4] += E);
      F = (digest[5] += F);
      G = (digest[6] += G);
      H = (digest[7] += H);
   }
}

std::string SHA_512_256::provider() const {
   return sha512_provider();
}

std::string SHA_384::provider() const {
   return sha512_provider();
}

std::string SHA_512::provider() const {
   return sha512_provider();
}

void SHA_512_256::compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
   SHA_512::compress_digest(digest, input, blocks);
}

void SHA_384::compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
   SHA_512::compress_digest(digest, input, blocks);
}

void SHA_512::compress_n(digest_type& digest, std::span<const uint8_t> input, size_t blocks) {
   SHA_512::compress_digest(digest, input, blocks);
}

void SHA_512_256::init(digest_type& digest) {
   digest.assign({0x22312194FC2BF72C,
                  0x9F555FA3C84C64C2,
                  0x2393B86B6F53B151,
                  0x963877195940EABD,
                  0x96283EE2A88EFFE3,
                  0xBE5E1E2553863992,
                  0x2B0199FC2C85B8AA,
                  0x0EB72DDC81C52CA2});
}

void SHA_384::init(digest_type& digest) {
   digest.assign({0xCBBB9D5DC1059ED8,
                  0x629A292A367CD507,
                  0x9159015A3070DD17,
                  0x152FECD8F70E5939,
                  0x67332667FFC00B31,
                  0x8EB44A8768581511,
                  0xDB0C2E0D64F98FA7,
                  0x47B5481DBEFA4FA4});
}

void SHA_512::init(digest_type& digest) {
   digest.assign({0x6A09E667F3BCC908,
                  0xBB67AE8584CAA73B,
                  0x3C6EF372FE94F82B,
                  0xA54FF53A5F1D36F1,
                  0x510E527FADE682D1,
                  0x9B05688C2B3E6C1F,
                  0x1F83D9ABFB41BD6B,
                  0x5BE0CD19137E2179});
}

std::unique_ptr<HashFunction> SHA_384::new_object() const {
   return std::make_unique<SHA_384>();
}

std::unique_ptr<HashFunction> SHA_512::new_object() const {
   return std::make_unique<SHA_512>();
}

std::unique_ptr<HashFunction> SHA_512_256::new_object() const {
   return std::make_unique<SHA_512_256>();
}

std::unique_ptr<HashFunction> SHA_384::copy_state() const {
   return std::make_unique<SHA_384>(*this);
}

std::unique_ptr<HashFunction> SHA_512::copy_state() const {
   return std::make_unique<SHA_512>(*this);
}

std::unique_ptr<HashFunction> SHA_512_256::copy_state() const {
   return std::make_unique<SHA_512_256>(*this);
}

void SHA_384::add_data(std::span<const uint8_t> input) {
   m_md.update(input);
}

void SHA_512::add_data(std::span<const uint8_t> input) {
   m_md.update(input);
}

void SHA_512_256::add_data(std::span<const uint8_t> input) {
   m_md.update(input);
}

void SHA_384::final_result(std::span<uint8_t> output) {
   m_md.final(output);
}

void SHA_512::final_result(std::span<uint8_t> output) {
   m_md.final(output);
}

void SHA_512_256::final_result(std::span<uint8_t> output) {
   m_md.final(output);
}

}  // namespace Botan
/*
* (C) 2016,2020 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

void Stateful_RNG::clear() {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);
   m_reseed_counter = 0;
   m_last_pid = 0;
   clear_state();
}

void Stateful_RNG::force_reseed() {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);
   m_reseed_counter = 0;
}

bool Stateful_RNG::is_seeded() const {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);
   return m_reseed_counter > 0;
}

void Stateful_RNG::initialize_with(std::span<const uint8_t> input) {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);

   clear();
   add_entropy(input);
}

void Stateful_RNG::generate_batched_output(std::span<uint8_t> output, std::span<const uint8_t> input) {
   BOTAN_ASSERT_NOMSG(!output.empty());

   const size_t max_per_request = max_number_of_bytes_per_request();

   if(max_per_request == 0) {
      // no limit
      reseed_check();
      this->generate_output(output, input);
   } else {
      while(!output.empty()) {
         const size_t this_req = std::min(max_per_request, output.size());

         reseed_check();
         this->generate_output(output.subspan(0, this_req), input);

         // only include the input for the first iteration
         input = {};

         output = output.subspan(this_req);
      }
   }
}

void Stateful_RNG::fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> input) {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);

   if(output.empty()) {
      // Special case for exclusively adding entropy to the stateful RNG.
      this->update(input);

      if(8 * input.size() >= security_level()) {
         reset_reseed_counter();
      }
   } else {
      generate_batched_output(output, input);
   }
}

size_t Stateful_RNG::reseed_from_sources(Entropy_Sources& srcs, size_t poll_bits) {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);

   const size_t bits_collected = RandomNumberGenerator::reseed_from_sources(srcs, poll_bits);

   if(bits_collected >= security_level()) {
      reset_reseed_counter();
   }

   return bits_collected;
}

void Stateful_RNG::reseed_from_rng(RandomNumberGenerator& rng, size_t poll_bits) {
   const lock_guard_type<recursive_mutex_type> lock(m_mutex);

   RandomNumberGenerator::reseed_from_rng(rng, poll_bits);

   if(poll_bits >= security_level()) {
      reset_reseed_counter();
   }
}

void Stateful_RNG::reset_reseed_counter() {
   // Lock is held whenever this function is called
   m_reseed_counter = 1;
   m_last_pid = OS::get_process_id();
}

void Stateful_RNG::reseed_check() {
   // Lock is held whenever this function is called

   const uint32_t cur_pid = OS::get_process_id();

   const bool fork_detected = (m_last_pid > 0) && (cur_pid != m_last_pid);

   if(is_seeded() == false || fork_detected || (m_reseed_interval > 0 && m_reseed_counter >= m_reseed_interval)) {
      m_reseed_counter = 0;
      m_last_pid = cur_pid;

      if(m_underlying_rng != nullptr) {
         reseed_from_rng(*m_underlying_rng, security_level());
      }

      if(m_entropy_sources != nullptr) {
         reseed_from_sources(*m_entropy_sources, security_level());
      }

      if(!is_seeded()) {
         if(fork_detected) {
            throw Invalid_State("Detected use of fork but cannot reseed DRBG");
         } else {
            throw PRNG_Unseeded(name());
         }
      }
   } else {
      BOTAN_ASSERT(m_reseed_counter != 0, "RNG is seeded");
      m_reseed_counter += 1;
   }
}

}  // namespace Botan
/*
* Stream Ciphers
* (C) 2015,2016 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_HAS_CHACHA)
#endif

#if defined(BOTAN_HAS_SALSA20)
#endif

#if defined(BOTAN_HAS_SHAKE_CIPHER)
#endif

#if defined(BOTAN_HAS_CTR_BE)
#endif

#if defined(BOTAN_HAS_OFB)
#endif

#if defined(BOTAN_HAS_RC4)
#endif

namespace Botan {

std::unique_ptr<StreamCipher> StreamCipher::create(std::string_view algo_spec, std::string_view provider) {
#if defined(BOTAN_HAS_SHAKE_CIPHER)
   if(algo_spec == "SHAKE-128" || algo_spec == "SHAKE-128-XOF") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<SHAKE_128_Cipher>();
      }
   }

   if(algo_spec == "SHAKE-256" || algo_spec == "SHAKE-256-XOF") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<SHAKE_256_Cipher>();
      }
   }
#endif

#if defined(BOTAN_HAS_CHACHA)
   if(algo_spec == "ChaCha20") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<ChaCha>(20);
      }
   }
#endif

#if defined(BOTAN_HAS_SALSA20)
   if(algo_spec == "Salsa20") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<Salsa20>();
      }
   }
#endif

   const SCAN_Name req(algo_spec);

#if defined(BOTAN_HAS_CTR_BE)
   if((req.algo_name() == "CTR-BE" || req.algo_name() == "CTR") && req.arg_count_between(1, 2)) {
      if(provider.empty() || provider == "base") {
         auto cipher = BlockCipher::create(req.arg(0));
         if(cipher) {
            const size_t ctr_size = req.arg_as_integer(1, cipher->block_size());
            return std::make_unique<CTR_BE>(std::move(cipher), ctr_size);
         }
      }
   }
#endif

#if defined(BOTAN_HAS_CHACHA)
   if(req.algo_name() == "ChaCha") {
      if(provider.empty() || provider == "base") {
         return std::make_unique<ChaCha>(req.arg_as_integer(0, 20));
      }
   }
#endif

#if defined(BOTAN_HAS_OFB)
   if(req.algo_name() == "OFB" && req.arg_count() == 1) {
      if(provider.empty() || provider == "base") {
         if(auto cipher = BlockCipher::create(req.arg(0))) {
            return std::make_unique<OFB>(std::move(cipher));
         }
      }
   }
#endif

#if defined(BOTAN_HAS_RC4)

   if(req.algo_name() == "RC4" || req.algo_name() == "ARC4" || req.algo_name() == "MARK-4") {
      const size_t skip = (req.algo_name() == "MARK-4") ? 256 : req.arg_as_integer(0, 0);

      if(provider.empty() || provider == "base") {
         return std::make_unique<RC4>(skip);
      }
   }

#endif

   BOTAN_UNUSED(req);
   BOTAN_UNUSED(provider);

   return nullptr;
}

//static
std::unique_ptr<StreamCipher> StreamCipher::create_or_throw(std::string_view algo, std::string_view provider) {
   if(auto sc = StreamCipher::create(algo, provider)) {
      return sc;
   }
   throw Lookup_Error("Stream cipher", algo, provider);
}

std::vector<std::string> StreamCipher::providers(std::string_view algo_spec) {
   return probe_providers_of<StreamCipher>(algo_spec);
}

void StreamCipher::cipher(std::span<const uint8_t> in, std::span<uint8_t> out) {
   BOTAN_ARG_CHECK(in.size() <= out.size(), "Output buffer of stream cipher must be at least as long as input buffer");
   cipher_bytes(in.data(), out.data(), in.size());
}

size_t StreamCipher::default_iv_length() const {
   return 0;
}

void StreamCipher::generate_keystream(uint8_t out[], size_t len) {
   clear_mem(out, len);
   cipher1(out, len);
}

}  // namespace Botan
/*
* System RNG
* (C) 2014,2015,2017,2018,2022 Jack Lloyd
* (C) 2021 Tom Crowley
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_TARGET_OS_HAS_WIN32)
   #define NOMINMAX 1
   #define _WINSOCKAPI_  // stop windows.h including winsock.h
   #include <windows.h>
#endif

#if defined(BOTAN_TARGET_OS_HAS_RTLGENRANDOM)
#elif defined(BOTAN_TARGET_OS_HAS_CRYPTO_NG)
   #include <bcrypt.h>
   #include <windows.h>
#elif defined(BOTAN_TARGET_OS_HAS_CCRANDOM)
   #include <CommonCrypto/CommonRandom.h>
#elif defined(BOTAN_TARGET_OS_HAS_ARC4RANDOM)
   #include <stdlib.h>
#elif defined(BOTAN_TARGET_OS_HAS_GETRANDOM)
   #include <errno.h>
   #include <sys/random.h>
   #include <sys/syscall.h>
   #include <unistd.h>
#elif defined(BOTAN_TARGET_OS_HAS_DEV_RANDOM)
   #include <errno.h>
   #include <fcntl.h>
   #include <unistd.h>
#endif

namespace Botan {

namespace {

#if defined(BOTAN_TARGET_OS_HAS_RTLGENRANDOM)

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      System_RNG_Impl() : m_advapi("advapi32.dll") {
         // This throws if the function is not found
         m_rtlgenrandom = m_advapi.resolve<RtlGenRandom_fptr>("SystemFunction036");
      }

      System_RNG_Impl(const System_RNG_Impl& other) = delete;
      System_RNG_Impl(System_RNG_Impl&& other) = delete;
      System_RNG_Impl& operator=(const System_RNG_Impl& other) = delete;
      System_RNG_Impl& operator=(System_RNG_Impl&& other) = delete;

      bool is_seeded() const override { return true; }

      bool accepts_input() const override { return false; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "RtlGenRandom"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override {
         const size_t limit = std::numeric_limits<ULONG>::max();

         uint8_t* pData = output.data();
         size_t bytesLeft = output.size();
         while(bytesLeft > 0) {
            const ULONG blockSize = static_cast<ULONG>(std::min(bytesLeft, limit));

            const bool success = m_rtlgenrandom(pData, blockSize) == TRUE;
            if(!success) {
               throw System_Error("RtlGenRandom failed");
            }

            BOTAN_ASSERT(bytesLeft >= blockSize, "Block is oversized");
            bytesLeft -= blockSize;
            pData += blockSize;
         }
      }

   private:
      using RtlGenRandom_fptr = BOOLEAN(NTAPI*)(PVOID, ULONG);

      Dynamically_Loaded_Library m_advapi;
      RtlGenRandom_fptr m_rtlgenrandom;
};

#elif defined(BOTAN_TARGET_OS_HAS_CRYPTO_NG)

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      System_RNG_Impl() {
         auto ret = ::BCryptOpenAlgorithmProvider(&m_prov, BCRYPT_RNG_ALGORITHM, MS_PRIMITIVE_PROVIDER, 0);
         if(!BCRYPT_SUCCESS(ret)) {
            throw System_Error("System_RNG failed to acquire crypto provider", ret);
         }
      }

      System_RNG_Impl(const System_RNG_Impl& other) = delete;
      System_RNG_Impl(System_RNG_Impl&& other) = delete;
      System_RNG_Impl& operator=(const System_RNG_Impl& other) = delete;
      System_RNG_Impl& operator=(System_RNG_Impl&& other) = delete;

      ~System_RNG_Impl() override { ::BCryptCloseAlgorithmProvider(m_prov, 0); }

      bool is_seeded() const override { return true; }

      bool accepts_input() const override { return false; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "crypto_ng"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override {
         /*
         There is a flag BCRYPT_RNG_USE_ENTROPY_IN_BUFFER to provide
         entropy inputs, but it is ignored in Windows 8 and later.
         */

         const size_t limit = std::numeric_limits<ULONG>::max();

         uint8_t* pData = output.data();
         size_t bytesLeft = output.size();
         while(bytesLeft > 0) {
            const ULONG blockSize = static_cast<ULONG>(std::min(bytesLeft, limit));

            auto ret = BCryptGenRandom(m_prov, static_cast<PUCHAR>(pData), blockSize, 0);
            if(!BCRYPT_SUCCESS(ret)) {
               throw System_Error("System_RNG call to BCryptGenRandom failed", ret);
            }

            BOTAN_ASSERT(bytesLeft >= blockSize, "Block is oversized");
            bytesLeft -= blockSize;
            pData += blockSize;
         }
      }

   private:
      BCRYPT_ALG_HANDLE m_prov;
};

#elif defined(BOTAN_TARGET_OS_HAS_CCRANDOM)

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      bool accepts_input() const override { return false; }

      bool is_seeded() const override { return true; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "CCRandomGenerateBytes"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override {
         if(::CCRandomGenerateBytes(output.data(), output.size()) != kCCSuccess) {
            throw System_Error("System_RNG CCRandomGenerateBytes failed", errno);
         }
      }
};

#elif defined(BOTAN_TARGET_OS_HAS_ARC4RANDOM)

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      // No constructor or destructor needed as no userland state maintained

      bool accepts_input() const override { return false; }

      bool is_seeded() const override { return true; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "arc4random"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override {
         // macOS 10.15 arc4random crashes if called with buf == nullptr && len == 0
         // however it uses ccrng_generate internally which returns a status, ignored
         // to respect arc4random "no-fail" interface contract
         if(!output.empty()) {
            ::arc4random_buf(output.data(), output.size());
         }
      }
};

#elif defined(BOTAN_TARGET_OS_HAS_GETRANDOM)

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      // No constructor or destructor needed as no userland state maintained

      bool accepts_input() const override { return false; }

      bool is_seeded() const override { return true; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "getrandom"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override {
         const unsigned int flags = 0;

         uint8_t* buf = output.data();
         size_t len = output.size();
         while(len > 0) {
   #if defined(__GLIBC__) && __GLIBC__ == 2 && __GLIBC_MINOR__ < 25
            const ssize_t got = ::syscall(SYS_getrandom, buf, len, flags);
   #else
            const ssize_t got = ::getrandom(buf, len, flags);
   #endif

            if(got < 0) {
               if(errno == EINTR) {
                  continue;
               }
               throw System_Error("System_RNG getrandom failed", errno);
            }

            if(got == 0) {
               throw System_Error("System_RNG getrandom unexpectedly returned 0");
            }

            buf += got;
            len -= got;
         }
      }
};

#elif defined(BOTAN_TARGET_OS_HAS_DEV_RANDOM)

// Read a random device

class System_RNG_Impl final : public RandomNumberGenerator {
   public:
      System_RNG_Impl() {
   #ifndef O_NOCTTY
      #define O_NOCTTY 0
   #endif

         /*
         * First open /dev/random and read one byte. On old Linux kernels
         * this blocks the RNG until we have been actually seeded.
         */
         m_fd = ::open("/dev/random", O_RDONLY | O_NOCTTY);
         if(m_fd < 0)
            throw System_Error("System_RNG failed to open RNG device", errno);

         uint8_t b;
         const size_t got = ::read(m_fd, &b, 1);
         ::close(m_fd);

         if(got != 1)
            throw System_Error("System_RNG failed to read blocking RNG device");

         m_fd = ::open("/dev/urandom", O_RDWR | O_NOCTTY);

         if(m_fd >= 0) {
            m_writable = true;
         } else {
            /*
            Cannot open in read-write mode. Fall back to read-only,
            calls to add_entropy will fail, but randomize will work
            */
            m_fd = ::open("/dev/urandom", O_RDONLY | O_NOCTTY);
            m_writable = false;
         }

         if(m_fd < 0)
            throw System_Error("System_RNG failed to open RNG device", errno);
      }

      System_RNG_Impl(const System_RNG_Impl& other) = delete;
      System_RNG_Impl(System_RNG_Impl&& other) = delete;
      System_RNG_Impl& operator=(const System_RNG_Impl& other) = delete;
      System_RNG_Impl& operator=(System_RNG_Impl&& other) = delete;

      ~System_RNG_Impl() override {
         ::close(m_fd);
         m_fd = -1;
      }

      bool is_seeded() const override { return true; }

      bool accepts_input() const override { return m_writable; }

      void clear() override { /* not possible */
      }

      std::string name() const override { return "urandom"; }

   private:
      void fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> /* ignored */) override;
      void maybe_write_entropy(std::span<const uint8_t> input);

   private:
      int m_fd;
      bool m_writable;
};

void System_RNG_Impl::fill_bytes_with_input(std::span<uint8_t> output, std::span<const uint8_t> input) {
   maybe_write_entropy(input);

   uint8_t* buf = output.data();
   size_t len = output.size();
   while(len) {
      ssize_t got = ::read(m_fd, buf, len);

      if(got < 0) {
         if(errno == EINTR)
            continue;
         throw System_Error("System_RNG read failed", errno);
      }
      if(got == 0)
         throw System_Error("System_RNG EOF on device");  // ?!?

      buf += got;
      len -= got;
   }
}

void System_RNG_Impl::maybe_write_entropy(std::span<const uint8_t> entropy_input) {
   if(!m_writable || entropy_input.empty())
      return;

   const uint8_t* input = entropy_input.data();
   size_t len = entropy_input.size();
   while(len) {
      ssize_t got = ::write(m_fd, input, len);

      if(got < 0) {
         if(errno == EINTR)
            continue;

         /*
         * This is seen on OS X CI, despite the fact that the man page
         * for macOS urandom explicitly states that writing to it is
         * supported, and write(2) does not document EPERM at all.
         * But in any case EPERM seems indicative of a policy decision
         * by the OS or sysadmin that additional entropy is not wanted
         * in the system pool, so we accept that and return here,
         * since there is no corrective action possible.
         *
         * In Linux EBADF or EPERM is returned if m_fd is not opened for
         * writing.
         */
         if(errno == EPERM || errno == EBADF)
            return;

         // maybe just ignore any failure here and return?
         throw System_Error("System_RNG write failed", errno);
      }

      input += got;
      len -= got;
   }
}

#endif

}  // namespace

RandomNumberGenerator& system_rng() {
   static System_RNG_Impl g_system_rng;
   return g_system_rng;
}

}  // namespace Botan
/*
* (C) 2017,2023 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <new>

#if defined(BOTAN_HAS_LOCKING_ALLOCATOR)
#endif

namespace Botan {

BOTAN_MALLOC_FN void* allocate_memory(size_t elems, size_t elem_size) {
   if(elems == 0 || elem_size == 0) {
      return nullptr;
   }

   // Some calloc implementations do not check for overflow (?!?)
   if(!checked_mul(elems, elem_size).has_value()) {
      throw std::bad_alloc();
   }

#if defined(BOTAN_HAS_LOCKING_ALLOCATOR)
   // NOLINTNEXTLINE(*-const-correctness) bug in clang-tidy
   if(void* p = mlock_allocator::instance().allocate(elems, elem_size)) {
      return p;
   }
#endif

#if defined(BOTAN_TARGET_OS_HAS_ALLOC_CONCEAL)
   void* ptr = ::calloc_conceal(elems, elem_size);
#else
   // NOLINTNEXTLINE(*-const-correctness) bug in clang-tidy
   void* ptr = std::calloc(elems, elem_size);  // NOLINT(*-no-malloc,*-owning-memory)
#endif
   if(ptr == nullptr) {
      [[unlikely]] throw std::bad_alloc();
   }
   return ptr;
}

void deallocate_memory(void* p, size_t elems, size_t elem_size) {
   if(p == nullptr) {
      [[unlikely]] return;
   }

   secure_scrub_memory(p, elems * elem_size);

#if defined(BOTAN_HAS_LOCKING_ALLOCATOR)
   if(mlock_allocator::instance().deallocate(p, elems, elem_size)) {
      return;
   }
#endif

   std::free(p);  // NOLINT(*-no-malloc,*-owning-memory)
}

void initialize_allocator() {
#if defined(BOTAN_HAS_LOCKING_ALLOCATOR)
   mlock_allocator::instance();
#endif
}

}  // namespace Botan
/*
* Runtime assertion checking
* (C) 2010,2012,2018 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



#if defined(BOTAN_TERMINATE_ON_ASSERTS)
   #include <iostream>
#endif

namespace Botan {

void throw_invalid_argument(const char* message, const char* func, const char* file) {
   throw Invalid_Argument(fmt("{} in {}:{}", message, func, file));
}

void throw_invalid_state(const char* expr, const char* func, const char* file) {
   throw Invalid_State(fmt("Invalid state: expr {} was false in {}:{}", expr, func, file));
}

// Declared in concepts.h
void ranges::memory_region_size_violation() {
   throw Invalid_Argument("Memory regions did not have expected byte lengths");
}

void assertion_failure(const char* expr_str, const char* assertion_made, const char* func, const char* file, int line) {
   std::ostringstream format;

   format << "False assertion ";

   if(assertion_made != nullptr && assertion_made[0] != 0) {
      format << "'" << assertion_made << "' (expression " << expr_str << ") ";
   } else {
      format << expr_str << " ";
   }

   if(func != nullptr) {
      format << "in " << func << " ";
   }

   format << "@" << file << ":" << line;

#if defined(BOTAN_TERMINATE_ON_ASSERTS)
   std::cerr << format.str() << '\n';
   std::abort();
#else
   throw Internal_Error(format.str());
#endif
}

void assert_unreachable(const char* file, int line) {
   const std::string msg = fmt("Codepath that was marked unreachable was reached @{}:{}", file, line);

#if defined(BOTAN_TERMINATE_ON_ASSERTS)
   std::cerr << msg << '\n';
   std::abort();
#else
   throw Internal_Error(msg);
#endif
}

}  // namespace Botan
/*
* Calendar Functions
* (C) 1999-2010,2017 Jack Lloyd
* (C) 2015 Simon Warta (Kullo GmbH)
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

/*
Portable replacement for timegm, _mkgmtime, etc

Algorithm due to Howard Hinnant

See https://howardhinnant.github.io/date_algorithms.html#days_from_civil
for details and explanation. The result is negative for dates before the epoch.
The code is slightly simplified by our assumption that the date is at least 1950,
which is sufficient for our purposes (ASN1_Time uses the same lower bound).
*/
int64_t days_since_epoch(uint32_t year, uint32_t month, uint32_t day) {
   BOTAN_ARG_CHECK(year >= 1950, "Years before 1950 not supported");

   if(month <= 2) {
      year -= 1;
   }
   const uint32_t era = year / 400;
   const uint32_t yoe = year - era * 400;                                          // [0, 399]
   const uint32_t doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;  // [0, 365]
   const uint32_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;                     // [0, 146096]
   return static_cast<int64_t>(era) * 146097 + static_cast<int64_t>(doe) - 719468;
}

/*
Portable replacement for gmtime, gmtime_r, _gmtime_s, etc

Algorithm due to Howard Hinnant

See https://howardhinnant.github.io/date_algorithms.html#civil_from_days
for details and explanation.
*/
std::array<uint32_t, 6> civil_from_time_point(const std::chrono::system_clock::time_point& tp) {
   const int64_t t = static_cast<int64_t>(std::chrono::system_clock::to_time_t(tp));

   // Split into days since epoch and seconds within the day, flooring towards
   // negative infinity so that times before the epoch are handled correctly.
   int64_t days = t / 86400;
   int64_t tod = t % 86400;
   if(tod < 0) {
      tod += 86400;
      days -= 1;
   }

   const int64_t z = days + 719468;
   const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
   const int64_t doe = z - era * 146097;                                       // [0, 146096]
   const int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;  // [0, 399]
   const int64_t y = yoe + era * 400;
   const int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);  // [0, 365]
   const int64_t mp = (5 * doy + 2) / 153;                       // [0, 11]
   const int64_t day = doy - (153 * mp + 2) / 5 + 1;             // [1, 31]
   const int64_t month = mp < 10 ? mp + 3 : mp - 9;              // [1, 12]
   const int64_t year = y + (month <= 2 ? 1 : 0);

   return {static_cast<uint32_t>(year),
           static_cast<uint32_t>(month),
           static_cast<uint32_t>(day),
           static_cast<uint32_t>(tod / 3600),
           static_cast<uint32_t>((tod % 3600) / 60),
           static_cast<uint32_t>(tod % 60)};
}

}  // namespace

calendar_point::calendar_point(uint32_t y, uint32_t mon, uint32_t d, uint32_t h, uint32_t min, uint32_t sec) :
      m_year(static_cast<uint16_t>(y)),
      m_month(static_cast<uint8_t>(mon)),
      m_day(static_cast<uint8_t>(d)),
      m_hour(static_cast<uint8_t>(h)),
      m_minutes(static_cast<uint8_t>(min)),
      m_seconds(static_cast<uint8_t>(sec)) {
   BOTAN_ARG_CHECK(y <= 9999, "Year is outside representable range");
   BOTAN_ARG_CHECK(mon >= 1 && mon <= 12, "Month is outside range");
   BOTAN_ARG_CHECK(d >= 1 && d <= 31, "Day is outside range");
   BOTAN_ARG_CHECK(h < 24, "Hour is outside range");
   BOTAN_ARG_CHECK(min < 60, "Minute is outside range");
   BOTAN_ARG_CHECK(sec < 60, "Seconds is outside range");
}

int64_t calendar_point::seconds_since_epoch() const {
   return (days_since_epoch(year(), month(), day()) * 86400) + (hour() * 60 * 60) + (minutes() * 60) + seconds();
}

std::chrono::system_clock::time_point calendar_point::to_std_timepoint() const {
   const int64_t seconds_64 = this->seconds_since_epoch();

   /*
   * The tick of a system_clock varies by implementation, and so also the
   * largest and smallest representable values vary. Ensure this date is within
   * range of the clock implementation.
   */
   constexpr int64_t max_representable_seconds = static_cast<int64_t>(
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::duration::max()).count());
   constexpr int64_t min_representable_seconds = static_cast<int64_t>(
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::duration::min()).count());

   if(seconds_64 > max_representable_seconds || seconds_64 < min_representable_seconds) {
      throw Invalid_Argument("calendar_point::to_std_timepoint time is outside the representable range");
   }

   const time_t seconds_time_t = static_cast<time_t>(seconds_64);

   if(seconds_64 - seconds_time_t != 0) {
      throw Invalid_Argument("calendar_point::to_std_timepoint time is outside the representable range");
   }

   return std::chrono::system_clock::from_time_t(seconds_time_t);
}

calendar_point::calendar_point(const std::chrono::system_clock::time_point& time_point) {
   const auto [year, month, day, hour, minute, second] = civil_from_time_point(time_point);

   BOTAN_ARG_CHECK(year <= 9999, "Year is outside representable range");

   m_year = static_cast<uint16_t>(year);
   m_month = static_cast<uint8_t>(month);
   m_day = static_cast<uint8_t>(day);
   m_hour = static_cast<uint8_t>(hour);
   m_minutes = static_cast<uint8_t>(minute);
   m_seconds = static_cast<uint8_t>(second);
}

}  // namespace Botan
/*
* Character Set Handling
* (C) 1999-2007,2021 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

void append_utf8_for(std::string& s, uint32_t c) {
   if(c >= 0xD800 && c < 0xE000) {
      throw Decoding_Error("Invalid Unicode character");
   }

   if(c <= 0x7F) {
      const uint8_t b0 = static_cast<uint8_t>(c);
      s.push_back(static_cast<char>(b0));
   } else if(c <= 0x7FF) {
      const uint8_t b0 = 0xC0 | static_cast<uint8_t>(c >> 6);
      const uint8_t b1 = 0x80 | static_cast<uint8_t>(c & 0x3F);
      s.push_back(static_cast<char>(b0));
      s.push_back(static_cast<char>(b1));
   } else if(c <= 0xFFFF) {
      const uint8_t b0 = 0xE0 | static_cast<uint8_t>(c >> 12);
      const uint8_t b1 = 0x80 | static_cast<uint8_t>((c >> 6) & 0x3F);
      const uint8_t b2 = 0x80 | static_cast<uint8_t>(c & 0x3F);
      s.push_back(static_cast<char>(b0));
      s.push_back(static_cast<char>(b1));
      s.push_back(static_cast<char>(b2));
   } else if(c <= 0x10FFFF) {
      const uint8_t b0 = 0xF0 | static_cast<uint8_t>(c >> 18);
      const uint8_t b1 = 0x80 | static_cast<uint8_t>((c >> 12) & 0x3F);
      const uint8_t b2 = 0x80 | static_cast<uint8_t>((c >> 6) & 0x3F);
      const uint8_t b3 = 0x80 | static_cast<uint8_t>(c & 0x3F);
      s.push_back(static_cast<char>(b0));
      s.push_back(static_cast<char>(b1));
      s.push_back(static_cast<char>(b2));
      s.push_back(static_cast<char>(b3));
   } else {
      throw Decoding_Error("Invalid Unicode character");
   }
}

}  // namespace

uint32_t next_utf8_codepoint(std::string_view utf8, size_t& pos) {
   auto read_continuation = [&]() -> uint32_t {
      if(pos >= utf8.size()) {
         throw Decoding_Error("Invalid UTF-8 sequence");
      }
      const uint8_t b = static_cast<uint8_t>(utf8[pos++]);
      if((b & 0xC0) != 0x80) {
         throw Decoding_Error("Invalid UTF-8 sequence");
      }
      return b & 0x3F;
   };

   if(pos >= utf8.size()) {
      throw Decoding_Error("Invalid UTF-8 sequence");
   }
   const uint8_t lead = static_cast<uint8_t>(utf8[pos++]);
   uint32_t c = 0;

   if(lead <= 0x7F) {
      c = lead;
   } else if((lead & 0xE0) == 0xC0) {
      c = (lead & 0x1F) << 6;
      c |= read_continuation();
      if(c < 0x80) {
         throw Decoding_Error("Overlong UTF-8 sequence");
      }
   } else if((lead & 0xF0) == 0xE0) {
      c = (lead & 0x0F) << 12;
      c |= read_continuation() << 6;
      c |= read_continuation();
      if(c < 0x800) {
         throw Decoding_Error("Overlong UTF-8 sequence");
      }
   } else if((lead & 0xF8) == 0xF0) {
      c = (lead & 0x07) << 18;
      c |= read_continuation() << 12;
      c |= read_continuation() << 6;
      c |= read_continuation();
      if(c < 0x10000) {
         throw Decoding_Error("Overlong UTF-8 sequence");
      }
   } else {
      throw Decoding_Error("Invalid UTF-8 sequence");
   }

   if(c > 0x10FFFF) {
      throw Decoding_Error("UTF-8 sequence encodes value outside Unicode range");
   }
   if(c >= 0xD800 && c < 0xE000) {
      throw Decoding_Error("UTF-8 sequence encodes surrogate code point");
   }

   return c;
}

bool is_valid_utf8(std::string_view utf8) {
   try {
      size_t pos = 0;
      while(pos < utf8.size()) {
         const uint32_t c = next_utf8_codepoint(utf8, pos);
         BOTAN_UNUSED(c);
      }
   } catch(Decoding_Error&) {
      return false;
   }
   return true;
}

std::string ucs2_to_utf8(std::span<const uint8_t> ucs2) {
   if(ucs2.size() % 2 != 0) {
      throw Decoding_Error("Invalid length for UCS-2 string");
   }

   const size_t chars = ucs2.size() / 2;

   std::string s;
   for(size_t i = 0; i != chars; ++i) {
      const uint32_t c = load_be<uint16_t>(ucs2.data(), i);
      append_utf8_for(s, c);
   }

   return s;
}

std::vector<uint8_t> utf8_to_ucs2(std::string_view utf8) {
   std::vector<uint8_t> out;
   out.reserve(utf8.size() * 2);

   size_t pos = 0;
   while(pos < utf8.size()) {
      const uint32_t c = next_utf8_codepoint(utf8, pos);
      if(c > 0xFFFF) {
         throw Decoding_Error("Cannot encode character in UCS-2");
      }
      const uint16_t val = static_cast<uint16_t>(c);
      out.push_back(get_byte<0>(val));
      out.push_back(get_byte<1>(val));
   }

   return out;
}

std::string ucs4_to_utf8(std::span<const uint8_t> ucs4) {
   if(ucs4.size() % 4 != 0) {
      throw Decoding_Error("Invalid length for UCS-4 string");
   }

   const size_t chars = ucs4.size() / 4;

   std::string s;
   for(size_t i = 0; i != chars; ++i) {
      const uint32_t c = load_be<uint32_t>(ucs4.data(), i);
      append_utf8_for(s, c);
   }

   return s;
}

std::vector<uint8_t> utf8_to_ucs4(std::string_view utf8) {
   std::vector<uint8_t> out;
   out.reserve(utf8.size() * 4);

   size_t pos = 0;
   while(pos < utf8.size()) {
      const uint32_t val = next_utf8_codepoint(utf8, pos);
      out.push_back(get_byte<0>(val));
      out.push_back(get_byte<1>(val));
      out.push_back(get_byte<2>(val));
      out.push_back(get_byte<3>(val));
   }

   return out;
}

/*
* Convert from ISO 8859-1 to UTF-8
*/
std::string latin1_to_utf8(std::span<const uint8_t> chars) {
   std::string s;
   for(const uint8_t b : chars) {
      append_utf8_for(s, static_cast<uint32_t>(b));
   }
   return s;
}

bool is_ascii_control_char(char c) {
   const uint8_t b = static_cast<uint8_t>(c);
   return b < 0x20 || b == 0x7F;
}

bool is_unicode_control_char(uint32_t cp) {
   return cp < 0x20 || (cp >= 0x7F && cp <= 0x9F);
}

std::string escape_control_chars(std::string_view utf8) {
   std::string out;
   out.reserve(utf8.size());

   const auto append_hex_escape = [&](uint8_t b) {
      out += "\\x";
      out += nibble_to_hex(b >> 4);
      out += nibble_to_hex(b);
   };

   size_t pos = 0;
   while(pos < utf8.size()) {
      const size_t start = pos;

      uint32_t cp = 0;
      try {
         cp = next_utf8_codepoint(utf8, pos);
      } catch(const Decoding_Error&) {
         // Not valid UTF-8: escape the offending byte and resume
         append_hex_escape(static_cast<uint8_t>(utf8[start]));
         pos = start + 1;
         continue;
      }

      if(is_unicode_control_char(cp)) {
         for(size_t i = start; i < pos; ++i) {
            append_hex_escape(static_cast<uint8_t>(utf8[i]));
         }
      } else {
         out.append(utf8.substr(start, pos - start));
      }
   }

   return out;
}

std::string format_char_for_display(char c) {
   std::string out;
   out += '\'';

   if(c == '\t') {
      out += "\\t";
   } else if(c == '\n') {
      out += "\\n";
   } else if(c == '\r') {
      out += "\\r";
   } else if(is_ascii_control_char(c) || static_cast<uint8_t>(c) >= 0x80) {
      const auto b = static_cast<uint8_t>(c);
      out += "\\x";
      out += nibble_to_hex(b >> 4);
      out += nibble_to_hex(b);
   } else {
      out += c;
   }

   out += '\'';

   return out;
}

}  // namespace Botan
/*
* (C) 2018,2021 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

CT::Option<size_t> CT::copy_output(CT::Choice accept,
                                   std::span<uint8_t> output,
                                   std::span<const uint8_t> input,
                                   size_t offset) {
   // This leaks information about the input length, but this happens
   // unavoidably since we are unable to ready any bytes besides those
   // in input[0..n]
   BOTAN_ARG_CHECK(output.size() >= input.size(), "Invalid span lengths");

   /*
   * We do not poison the input here because if we did we would have
   * to unpoison it at exit. We assume instead that callers have
   * already poisoned the input and will unpoison it at their own
   * time.
   */
   CT::poison(offset);

   /**
   * Zeroize the entire output buffer to get started
   */
   clear_mem(output);

   /*
   * If the offset is greater than input length, then the arguments are
   * invalid. Ideally we would throw an exception, but that leaks
   * information about the offset. Instead treat it as if the input
   * was invalid.
   */
   accept = accept && CT::Mask<size_t>::is_lte(offset, input.size()).as_choice();

   /*
   * If the input is invalid, then set offset == input_length
   */
   offset = CT::Mask<size_t>::from_choice(accept).select(offset, input.size());

   /*
   * Move the desired output bytes to the front using a slow (O^n)
   * but constant time loop that does not leak the value of the offset
   */
   for(size_t i = 0; i != input.size(); ++i) {
      /*
      * If bad_input was set then we modified offset to equal the input_length.
      * In that case, this_loop will be greater than input_length, and so is_eq
      * mask will always be false. As a result none of the input values will be
      * written to output.
      *
      * This is ignoring the possibility of integer overflow of offset + i. But
      * for this to happen the input would have to consume nearly the entire
      * address space.
      */
      const size_t this_loop = offset + i;

      /*
      start index from i rather than 0 since we know j must be >= i + offset
      to have any effect, and starting from i does not reveal information
      */
      for(size_t j = i; j != input.size(); ++j) {
         const uint8_t b = input[j];
         const auto is_eq = CT::Mask<size_t>::is_equal(j, this_loop);
         output[i] |= is_eq.if_set_return(b);
      }
   }

   // This will always be zero if the input was invalid
   const size_t output_bytes = input.size() - offset;

   CT::unpoison_all(output, output_bytes);

   return CT::Option<size_t>(output_bytes, accept);
}

size_t CT::count_leading_zero_bytes(std::span<const uint8_t> input) {
   size_t leading_zeros = 0;
   auto only_zeros = Mask<uint8_t>::set();
   for(const uint8_t b : input) {
      only_zeros &= CT::Mask<uint8_t>::is_zero(b);
      leading_zeros += only_zeros.if_set_return(1);
   }
   return leading_zeros;
}

secure_vector<uint8_t> CT::strip_leading_zeros(std::span<const uint8_t> input) {
   const size_t leading_zeros = CT::count_leading_zero_bytes(input);

   secure_vector<uint8_t> output(input.size());

   const auto written = CT::copy_output(CT::Choice::yes(), output, input, leading_zeros);

   /*
   This is potentially not const time, depending on how std::vector is
   implemented. But since we are always reducing length, it should
   just amount to setting the member var holding the length.
   */
   output.resize(written.value_or(0));

   return output;
}

}  // namespace Botan
/*
* DataSource
* (C) 1999-2007 Jack Lloyd
*     2005 Matthew Gregan
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <istream>

#if defined(BOTAN_TARGET_OS_HAS_FILESYSTEM)
   #include <fstream>
#endif

namespace Botan {

/*
* Read a single byte from the DataSource
*/
size_t DataSource::read_byte(uint8_t& out) {
   return read(&out, 1);
}

/*
* Read a single byte from the DataSource
*/
std::optional<uint8_t> DataSource::read_byte() {
   uint8_t b = 0;
   if(this->read(&b, 1) == 1) {
      return b;
   } else {
      return {};
   }
}

/*
* Peek a single byte from the DataSource
*/
size_t DataSource::peek_byte(uint8_t& out) const {
   return peek(&out, 1, 0);
}

/*
* Discard the next N bytes of the data
*/
size_t DataSource::discard_next(size_t n) {
   uint8_t buf[64] = {0};
   size_t discarded = 0;

   while(n > 0) {
      const size_t got = this->read(buf, std::min(n, sizeof(buf)));
      discarded += got;
      n -= got;

      if(got == 0) {
         break;
      }
   }

   return discarded;
}

/*
* Read from a memory buffer
*/
size_t DataSource_Memory::read(uint8_t out[], size_t length) {
   const size_t got = std::min<size_t>(m_source.size() - m_offset, length);
   copy_mem(out, m_source.data() + m_offset, got);
   m_offset += got;
   return got;
}

bool DataSource_Memory::check_available(size_t n) {
   return (n <= (m_source.size() - m_offset));
}

/*
* Peek into a memory buffer
*/
size_t DataSource_Memory::peek(uint8_t out[], size_t length, size_t peek_offset) const {
   const size_t bytes_left = m_source.size() - m_offset;
   if(peek_offset >= bytes_left) {
      return 0;
   }

   const size_t got = std::min(bytes_left - peek_offset, length);
   copy_mem(out, &m_source[m_offset + peek_offset], got);
   return got;
}

/*
* Check if the memory buffer is empty
*/
bool DataSource_Memory::end_of_data() const {
   return (m_offset == m_source.size());
}

/*
* DataSource_Memory Constructor
*/
DataSource_Memory::DataSource_Memory(std::string_view in) : DataSource_Memory(as_span_of_bytes(in)) {}

/*
* Read from a stream
*/
size_t DataSource_Stream::read(uint8_t out[], size_t length) {
   m_source.read(cast_uint8_ptr_to_char(out), length);
   if(m_source.bad()) {
      throw Stream_IO_Error("DataSource_Stream::read: Source failure");
   }

   const size_t got = static_cast<size_t>(m_source.gcount());
   m_total_read += got;
   return got;
}

bool DataSource_Stream::check_available(size_t n) {
   const std::streampos orig_pos = m_source.tellg();
   m_source.seekg(0, std::ios::end);
   const size_t avail = static_cast<size_t>(m_source.tellg() - orig_pos);
   m_source.seekg(orig_pos);
   return (avail >= n);
}

/*
* Peek into a stream
*/
size_t DataSource_Stream::peek(uint8_t out[], size_t length, size_t offset) const {
   if(end_of_data()) {
      throw Invalid_State("DataSource_Stream: Cannot peek when out of data");
   }

   size_t got = 0;

   if(offset > 0) {
      m_source.seekg(offset, std::ios::cur);
      if(!m_source.good()) {
         m_source.clear();
         m_source.seekg(m_total_read, std::ios::beg);
         return 0;
      }
   }

   m_source.read(cast_uint8_ptr_to_char(out), length);
   if(m_source.bad()) {
      throw Stream_IO_Error("DataSource_Stream::peek: Source failure");
   }
   got = static_cast<size_t>(m_source.gcount());

   if(m_source.eof()) {
      m_source.clear();
   }
   m_source.seekg(m_total_read, std::ios::beg);

   return got;
}

/*
* Check if the stream is empty or in error
*/
bool DataSource_Stream::end_of_data() const {
   /*
   Peek to trigger EOF indicator if positioned at the end of the stream.
   Without this, good() returns true even when all data has been read.
   */
   m_source.peek();
   return (!m_source.good());
}

/*
* Return a human-readable ID for this stream
*/
std::string DataSource_Stream::id() const {
   return m_identifier;
}

#if defined(BOTAN_TARGET_OS_HAS_FILESYSTEM)

/*
* DataSource_Stream Constructor
*/
DataSource_Stream::DataSource_Stream(std::string_view path, bool use_binary) :
      m_identifier(path),
      m_source_memory(std::make_unique<std::ifstream>(std::string(path), use_binary ? std::ios::binary : std::ios::in)),
      m_source(*m_source_memory),
      m_total_read(0) {
   if(!m_source.good()) {
      throw Stream_IO_Error(fmt("DataSource: Failure opening file '{}'", path));
   }
}

#endif

/*
* DataSource_Stream Constructor
*/
DataSource_Stream::DataSource_Stream(std::istream& in, std::string_view name) :
      m_identifier(name), m_source(in), m_total_read(0) {}

DataSource_Stream::~DataSource_Stream() = default;

}  // namespace Botan
/*
* (C) 2026 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <string>

namespace Botan {

bool SQL_Database::is_valid_table_name(std::string_view table) const {
   if(table.empty()) {
      return false;
   }

   constexpr auto valid_table_name_char = CharacterValidityTable::alpha_numeric_plus("_");
   for(const char c : table) {
      if(!valid_table_name_char(c)) {
         return false;
      }
   }
   return true;
}

std::shared_ptr<SQL_Database::Statement> SQL_Database::select(std::string_view columns,
                                                              std::string_view table,
                                                              std::string_view where,
                                                              std::optional<size_t> limit) const {
   std::string sql = "SELECT ";
   sql += columns;
   sql += " FROM ";
   sql += table;
   if(!where.empty()) {
      sql += " WHERE ";
      sql += where;
   }
   if(limit.has_value()) {
      sql += " LIMIT ";
      sql += std::to_string(*limit);
   }
   return new_statement(sql);
}

}  // namespace Botan
/*
* (C) 2017 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

std::string to_string(ErrorType type) {
   switch(type) {
      case ErrorType::Unknown:
         return "Unknown";
      case ErrorType::SystemError:
         return "SystemError";
      case ErrorType::NotImplemented:
         return "NotImplemented";
      case ErrorType::OutOfMemory:
         return "OutOfMemory";
      case ErrorType::InternalError:
         return "InternalError";
      case ErrorType::IoError:
         return "IoError";
      case ErrorType::InvalidObjectState:
         return "InvalidObjectState";
      case ErrorType::KeyNotSet:
         return "KeyNotSet";
      case ErrorType::InvalidArgument:
         return "InvalidArgument";
      case ErrorType::InvalidKeyLength:
         return "InvalidKeyLength";
      case ErrorType::InvalidNonceLength:
         return "InvalidNonceLength";
      case ErrorType::LookupError:
         return "LookupError";
      case ErrorType::EncodingFailure:
         return "EncodingFailure";
      case ErrorType::DecodingFailure:
         return "DecodingFailure";
      case ErrorType::TLSError:
         return "TLSError";
      case ErrorType::HttpError:
         return "HttpError";
      case ErrorType::InvalidTag:
         return "InvalidTag";
      case ErrorType::RoughtimeError:
         return "RoughtimeError";
      case ErrorType::CommonCryptoError:
         return "CommonCryptoError";
      case ErrorType::Pkcs11Error:
         return "Pkcs11Error";
      case ErrorType::TPMError:
         return "TPMError";
      case ErrorType::DatabaseError:
         return "DatabaseError";
      case ErrorType::ZlibError:
         return "ZlibError";
      case ErrorType::Bzip2Error:
         return "Bzip2Error";
      case ErrorType::LzmaError:
         return "LzmaError";
   }

   // No default case in above switch so compiler warns
   return "Unrecognized Botan error";
}

Exception::Exception(std::string_view msg) : m_msg(msg) {}

Exception::Exception(std::string_view msg, const std::exception& e) : m_msg(fmt("{} failed with {}", msg, e.what())) {}

Exception::Exception(const char* prefix, std::string_view msg) : m_msg(fmt("{} {}", prefix, msg)) {}

Invalid_Argument::Invalid_Argument(std::string_view msg) : Exception(msg) {}

Invalid_Argument::Invalid_Argument(std::string_view msg, std::string_view where) :
      Exception(fmt("{} in {}", msg, where)) {}

Invalid_Argument::Invalid_Argument(std::string_view msg, const std::exception& e) : Exception(msg, e) {}

namespace {

std::string format_lookup_error(std::string_view type, std::string_view algo, std::string_view provider) {
   if(provider.empty()) {
      return fmt("Unavailable {} {}", type, algo);
   } else {
      return fmt("Unavailable {} {} for provider {}", type, algo, provider);
   }
}

}  // namespace

Lookup_Error::Lookup_Error(std::string_view type, std::string_view algo, std::string_view provider) :
      Exception(format_lookup_error(type, algo, provider)) {}

Internal_Error::Internal_Error(std::string_view err) : Exception("Internal error:", err) {}

Unknown_PK_Field_Name::Unknown_PK_Field_Name(std::string_view algo_name, std::string_view field_name) :
      Invalid_Argument(fmt("Unknown field '{}' for algorithm {}", field_name, algo_name)) {}

Invalid_Key_Length::Invalid_Key_Length(std::string_view name, size_t length) :
      Invalid_Argument(fmt("{} cannot accept a key of length {}", name, length)) {}

Invalid_IV_Length::Invalid_IV_Length(std::string_view mode, size_t bad_len) :
      Invalid_Argument(fmt("IV length {} is invalid for {}", bad_len, mode)) {}

Key_Not_Set::Key_Not_Set(std::string_view algo) : Invalid_State(fmt("Key not set in {}", algo)) {}

PRNG_Unseeded::PRNG_Unseeded(std::string_view algo) : Invalid_State(fmt("PRNG {} not seeded", algo)) {}

Algorithm_Not_Found::Algorithm_Not_Found(std::string_view name) :
      Lookup_Error(fmt("Could not find any algorithm named '{}'", name)) {}

Provider_Not_Found::Provider_Not_Found(std::string_view algo, std::string_view provider) :
      Lookup_Error(fmt("Could not find provider '{}' for algorithm '{}'", provider, algo)) {}

Invalid_Algorithm_Name::Invalid_Algorithm_Name(std::string_view name) :
      Invalid_Argument(fmt("Invalid algorithm name: '{}'", name)) {}

Encoding_Error::Encoding_Error(std::string_view name) : Exception("Encoding error:", name) {}

Decoding_Error::Decoding_Error(std::string_view name) : Exception(name) {}

Decoding_Error::Decoding_Error(std::string_view category, std::string_view err) :
      Exception(fmt("{}: {}", category, err)) {}

Decoding_Error::Decoding_Error(std::string_view msg, const std::exception& e) : Exception(msg, e) {}

Invalid_Authentication_Tag::Invalid_Authentication_Tag(std::string_view msg) :
      Exception("Invalid authentication tag:", msg) {}

Stream_IO_Error::Stream_IO_Error(std::string_view err) : Exception("I/O error:", err) {}

System_Error::System_Error(std::string_view msg, int err_code) :
      Exception(fmt("{} error code {}", msg, err_code)), m_error_code(err_code) {}

Not_Implemented::Not_Implemented(std::string_view err) : Exception("Not implemented", err) {}

}  // namespace Botan
/*
* (C) 2015,2017,2019 Jack Lloyd
* (C) 2015 Simon Warta (Kullo GmbH)
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <deque>

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   #include <dirent.h>
   #include <functional>
   #include <sys/stat.h>
   #include <sys/types.h>
#elif defined(BOTAN_TARGET_OS_HAS_WIN32)
   #define NOMINMAX 1
   #define _WINSOCKAPI_  // stop windows.h including winsock.h
   #include <windows.h>
#endif

namespace Botan {

namespace {

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)

std::vector<std::string> impl_readdir(std::string_view dir_path) {
   std::vector<std::string> out;
   std::deque<std::string> dir_list;
   dir_list.push_back(std::string(dir_path));

   while(!dir_list.empty()) {
      const std::string cur_path = dir_list[0];
      dir_list.pop_front();

      const std::unique_ptr<DIR, std::function<int(DIR*)>> dir(::opendir(cur_path.c_str()), ::closedir);

      if(dir) {
         while(struct dirent* dirent = ::readdir(dir.get())) {
            const std::string filename = dirent->d_name;
            if(filename == "." || filename == "..") {
               continue;
            }

            std::ostringstream full_path_sstr;
            full_path_sstr << cur_path << "/" << filename;
            const std::string full_path = full_path_sstr.str();

            struct stat stat_buf {};

            if(::stat(full_path.c_str(), &stat_buf) == -1) {
               continue;
            }

            if(S_ISDIR(stat_buf.st_mode)) {
               dir_list.push_back(full_path);
            } else if(S_ISREG(stat_buf.st_mode)) {
               out.push_back(full_path);
            }
         }
      }
   }

   return out;
}

#elif defined(BOTAN_TARGET_OS_HAS_WIN32)

std::vector<std::string> impl_win32(std::string_view dir_path) {
   std::vector<std::string> out;
   std::deque<std::string> dir_list;
   dir_list.push_back(std::string(dir_path));

   while(!dir_list.empty()) {
      const std::string cur_path = dir_list[0];
      dir_list.pop_front();

      WIN32_FIND_DATAA find_data;
      HANDLE dir = ::FindFirstFileA((cur_path + "/*").c_str(), &find_data);

      if(dir != INVALID_HANDLE_VALUE) {
         do {
            const std::string filename = find_data.cFileName;
            if(filename == "." || filename == "..")
               continue;
            const std::string full_path = cur_path + "/" + filename;

            if(find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
               dir_list.push_back(full_path);
            } else {
               out.push_back(full_path);
            }
         } while(::FindNextFileA(dir, &find_data));
      }

      ::FindClose(dir);
   }

   return out;
}
#endif

}  // namespace

bool has_filesystem_impl() {
#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   return true;
#elif defined(BOTAN_TARGET_OS_HAS_WIN32)
   return true;
#else
   return false;
#endif
}

std::vector<std::string> get_files_recursive(std::string_view dir) {
   std::vector<std::string> files;

#if defined(BOTAN_TARGET_OS_HAS_POSIX1)
   files = impl_readdir(dir);
#elif defined(BOTAN_TARGET_OS_HAS_WIN32)
   files = impl_win32(dir);
#else
   BOTAN_UNUSED(dir);
   throw No_Filesystem_Access();
#endif

   std::sort(files.begin(), files.end());

   return files;
}

}  // namespace Botan
/*
* (C) 2017 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

uint8_t ct_compare_u8(const uint8_t x[], const uint8_t y[], size_t len) {
   return CT::is_equal(x, y, len).value();
}

bool constant_time_compare(std::span<const uint8_t> x, std::span<const uint8_t> y) {
   const auto min_size = CT::Mask<size_t>::is_lte(x.size(), y.size()).select(x.size(), y.size());
   const auto equal_size = CT::Mask<size_t>::is_equal(x.size(), y.size());
   const auto equal_content = CT::Mask<size_t>::expand(CT::is_equal(x.data(), y.data(), min_size));
   return (equal_content & equal_size).as_bool();
}

}  // namespace Botan
/*
* (C) 2025 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <cstring>

#if defined(BOTAN_TARGET_OS_HAS_EXPLICIT_BZERO)
   #include <string.h>
#endif

#if defined(BOTAN_TARGET_OS_HAS_RTLSECUREZEROMEMORY)
   #define NOMINMAX 1
   #define _WINSOCKAPI_  // stop windows.h including winsock.h
   #include <windows.h>
#endif

namespace Botan {

void secure_scrub_memory(void* ptr, size_t n) {
   return secure_zeroize_buffer(ptr, n);
}

void secure_zeroize_buffer(void* ptr, size_t n) {
   if(n == 0) {
      return;
   }

#if defined(BOTAN_TARGET_OS_HAS_RTLSECUREZEROMEMORY)
   ::RtlSecureZeroMemory(ptr, n);

#elif defined(BOTAN_TARGET_OS_HAS_EXPLICIT_BZERO)
   ::explicit_bzero(ptr, n);

#elif defined(BOTAN_TARGET_OS_HAS_EXPLICIT_MEMSET)
   (void)::explicit_memset(ptr, 0, n);

#else
   /*
   * Call memset through a static volatile pointer, which the compiler should
   * not elide. This construct should be safe in conforming compilers, but who
   * knows. This has been checked to generate the expected code, which saves the
   * memset address in the data segment and unconditionally loads and jumps to
   * that address, with the following targets:
   *
   * x86-64: Clang 19, GCC 6, 11, 13, 14
   * riscv64: GCC 14
   * aarch64: GCC 14
   * armv7: GCC 14
   *
   * Actually all of them generated the expected jump even without marking the
   * function pointer as volatile. However this seems worth including as an
   * additional precaution.
   */
   static void* (*const volatile memset_ptr)(void*, int, size_t) = std::memset;
   (memset_ptr)(ptr, 0, n);
#endif
}

}  // namespace Botan
/*
* Various string utils and parsing functions
* (C) 1999-2007,2013,2014,2015,2018 Jack Lloyd
* (C) 2015 Simon Warta (Kullo GmbH)
* (C) 2017 René Korthaus, Rohde & Schwarz Cybersecurity
*
* Botan is released under the Simplified BSD License (see license.txt)
*/


#include <concepts>

namespace Botan {

namespace {

std::optional<size_t> digit_from_ascii(char c) {
   if(c >= '0' && c <= '9') {
      return c - '0';
   } else {
      return {};
   }
}

template <std::unsigned_integral T>
std::optional<T> parse_decimal_integer(std::string_view input, bool require_canonical) {
   if(input.empty() || input.size() > (std::numeric_limits<T>::digits10 + 1)) {
      return {};
   }

   // The canonical encoding of zero is "0"; no other value starts with a zero
   if(require_canonical && input.size() > 1 && input.front() == '0') {
      return {};
   }

   T accum = 0;

   for(const char c : input) {
      if(const auto digit = digit_from_ascii(c)) {
         if(accum > (std::numeric_limits<T>::max() - static_cast<T>(*digit)) / 10) {
            return {};
         }
         accum = accum * 10 + static_cast<T>(*digit);
      } else {
         return {};
      }
   }

   return accum;
}

}  // namespace

std::optional<uint16_t> parse_u16(std::string_view input, bool require_canonical) {
   return parse_decimal_integer<uint16_t>(input, require_canonical);
}

std::optional<uint32_t> parse_u32(std::string_view input, bool require_canonical) {
   return parse_decimal_integer<uint32_t>(input, require_canonical);
}

std::optional<uint64_t> parse_u64(std::string_view input, bool require_canonical) {
   return parse_decimal_integer<uint64_t>(input, require_canonical);
}

std::optional<size_t> parse_sz(std::string_view input, bool require_canonical) {
   return parse_decimal_integer<size_t>(input, require_canonical);
}

uint32_t to_u32bit(std::string_view input) {
   if(const auto parsed = parse_u32(input)) {
      return *parsed;
   } else {
      throw Invalid_Argument(fmt("Failed to parse input '{}' as a 32-bit integer", input));
   }
}

/*
* Parse a SCAN-style algorithm name
*/
std::vector<std::string> parse_algorithm_name(std::string_view scan_name) {
   if(scan_name.find('(') == std::string::npos && scan_name.find(')') == std::string::npos) {
      return {std::string(scan_name)};
   }

   std::string name(scan_name);
   std::string substring;
   std::vector<std::string> elems;
   size_t level = 0;

   elems.push_back(name.substr(0, name.find('(')));
   name = name.substr(name.find('('));

   for(auto i = name.begin(); i != name.end(); ++i) {
      const char c = *i;

      if(c == '(') {
         ++level;
      }
      if(c == ')') {
         if(level == 1 && i == name.end() - 1) {
            if(elems.size() == 1) {
               elems.push_back(substring.substr(1));
            } else {
               elems.push_back(substring);
            }
            return elems;
         }

         if(level == 0 || (level == 1 && i != name.end() - 1)) {
            throw Invalid_Algorithm_Name(scan_name);
         }
         --level;
      }

      if(c == ',' && level == 1) {
         if(elems.size() == 1) {
            elems.push_back(substring.substr(1));
         } else {
            elems.push_back(substring);
         }
         substring.clear();
      } else {
         substring += c;
      }
   }

   if(!substring.empty()) {
      throw Invalid_Algorithm_Name(scan_name);
   }

   return elems;
}

std::vector<std::string> split_on(std::string_view str, char delim) {
   std::vector<std::string> elems;
   if(str.empty()) {
      return elems;
   }

   std::string substr;
   for(const char c : str) {
      if(c == delim) {
         if(!substr.empty()) {
            elems.push_back(substr);
         }
         substr.clear();
      } else {
         substr += c;
      }
   }

   if(substr.empty()) {
      throw Invalid_Argument(fmt("Unable to split string '{}", str));
   }
   elems.push_back(substr);

   return elems;
}

/*
* Join a string
*/
std::string string_join(const std::vector<std::string>& strs, char delim) {
   std::ostringstream out;

   for(size_t i = 0; i != strs.size(); ++i) {
      if(i != 0) {
         out << delim;
      }
      out << strs[i];
   }

   return out.str();
}

std::string tolower_string(std::string_view str) {
   // Locale-independent ASCII fold; the only callers (DNS name canonicalization
   // for SAN/name-constraints) work on ASCII strings per RFC 1035.
   std::string lower(str);
   for(char& c : lower) {
      if(c >= 'A' && c <= 'Z') {
         c = static_cast<char>(c + ('a' - 'A'));
      }
   }
   return lower;
}

}  // namespace Botan
/*
* (C) 2023 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

uint64_t prefetch_array_raw(size_t bytes, const void* arrayv) noexcept {
#if defined(__cpp_lib_hardware_interference_size)
   constexpr size_t cache_line_size = std::hardware_destructive_interference_size;
#else
   // We arbitrarily use a 64 byte cache line, which is by far the most
   // common size.
   //
   // Runtime detection adds too much overhead to this function.
   constexpr size_t cache_line_size = 64;
#endif

   const uint8_t* array = static_cast<const uint8_t*>(arrayv);

   volatile uint64_t combiner = 1;

   for(size_t idx = 0; idx < bytes; idx += cache_line_size) {
#if BOTAN_COMPILER_HAS_BUILTIN(__builtin_prefetch)
      // we have no way of knowing if the compiler will emit anything here
      __builtin_prefetch(&array[idx]);
#endif

      combiner = combiner | array[idx];
   }

   /*
   * The combiner variable is initialized with 1, and we accumulate using OR, so
   * now combiner must be a value other than zero. This being the case we will
   * always return zero here. Hopefully the compiler will not figure this out.
   */
   return ct_is_zero(combiner);
}

}  // namespace Botan
/*
* Simple config/test file reader
* (C) 2013,2014,2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

std::string clean_ws(std::string_view s) {
   const char* ws = " \t\n";
   auto start = s.find_first_not_of(ws);
   auto end = s.find_last_not_of(ws);

   if(start == std::string::npos) {
      return "";
   }

   if(end == std::string::npos) {
      return std::string(s.substr(start, end));
   } else {
      return std::string(s.substr(start, start + end + 1));
   }
}

}  // namespace

std::map<std::string, std::string> read_cfg(std::istream& is) {
   std::map<std::string, std::string> kv;
   size_t line = 0;

   while(is.good()) {
      std::string s;

      std::getline(is, s);

      ++line;

      if(s.empty() || s[0] == '#') {
         continue;
      }

      s = clean_ws(s.substr(0, s.find('#')));

      if(s.empty()) {
         continue;
      }

      auto eq = s.find('=');

      if(eq == std::string::npos || eq == 0 || eq == s.size() - 1) {
         throw Decoding_Error("Bad read_cfg input '" + s + "' on line " + std::to_string(line));
      }

      const std::string key = clean_ws(s.substr(0, eq));
      const std::string val = clean_ws(s.substr(eq + 1, std::string::npos));

      kv[key] = val;
   }

   return kv;
}

}  // namespace Botan
/*
* (C) 2018 Ribose Inc
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

std::map<std::string, std::string> read_kv(std::string_view kv) {
   std::map<std::string, std::string> m;
   if(kv.empty()) {
      return m;
   }

   std::vector<std::string> parts;

   try {
      parts = split_on(kv, ',');
   } catch(std::exception&) {
      throw Invalid_Argument("Bad KV spec");
   }

   bool escaped = false;
   bool reading_key = true;
   std::string cur_key;
   std::string cur_val;

   for(const char c : kv) {
      if(c == '\\' && !escaped) {
         escaped = true;
      } else if(c == ',' && !escaped) {
         if(cur_key.empty()) {
            throw Invalid_Argument("Bad KV spec empty key");
         }

         if(m.contains(cur_key)) {
            throw Invalid_Argument("Bad KV spec duplicated key");
         }
         m[cur_key] = cur_val;
         cur_key = "";
         cur_val = "";
         reading_key = true;
      } else if(c == '=' && !escaped) {
         if(!reading_key) {
            throw Invalid_Argument("Bad KV spec unexpected equals sign");
         }
         reading_key = false;
      } else {
         if(reading_key) {
            cur_key += c;
         } else {
            cur_val += c;
         }

         if(escaped) {
            escaped = false;
         }
      }
   }

   if(!cur_key.empty()) {
      if(!reading_key) {
         if(m.contains(cur_key)) {
            throw Invalid_Argument("Bad KV spec duplicated key");
         }
         m[cur_key] = cur_val;
      } else {
         throw Invalid_Argument("Bad KV spec incomplete string");
      }
   }

   return m;
}

}  // namespace Botan
/*
* SCAN Name Abstraction
* (C) 2008-2009,2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

namespace {

std::string make_arg(const std::vector<std::pair<size_t, std::string>>& name, size_t start) {
   std::string output = name[start].second;
   size_t level = name[start].first;

   size_t paren_depth = 0;

   for(size_t i = start + 1; i != name.size(); ++i) {
      if(name[i].first <= name[start].first) {
         break;
      }

      if(name[i].first > level) {
         for(size_t j = level; j < name[i].first; j++) {
            output += "(";
            ++paren_depth;
         }
         output += name[i].second;
      } else if(name[i].first < level) {
         for(size_t j = name[i].first; j < level; j++) {
            output += ")";
            BOTAN_ASSERT_NOMSG(paren_depth != 0);
            --paren_depth;
         }
         output += "," + name[i].second;
      } else {
         if(output[output.size() - 1] != '(') {
            output += ",";
         }
         output += name[i].second;
      }

      level = name[i].first;
   }

   for(size_t i = 0; i != paren_depth; ++i) {
      output += ")";
   }

   return output;
}

}  // namespace

SCAN_Name::SCAN_Name(std::string_view algo_spec) : m_orig_algo_spec(algo_spec) {
   if(algo_spec.empty()) {
      throw Invalid_Argument("Expected algorithm name, got empty string");
   }

   // Fast path for a bare name with no arguments or modes (eg "SHA-256"),
   // which is the common case. Equivalent to the general parse below, which
   // for such input produces a single token and no args/modes.
   if(algo_spec.find_first_of("(),/") == std::string_view::npos) {
      m_alg_name = std::string(algo_spec);
      return;
   }

   std::vector<std::pair<size_t, std::string>> name;
   size_t level = 0;
   std::pair<size_t, std::string> accum = std::make_pair(level, "");

   bool expect_token = true;

   for(const char c : algo_spec) {
      if(c == '/' || c == ',' || c == '(' || c == ')') {
         if(c == '(') {
            ++level;
         } else if(c == ')') {
            if(level == 0) {
               throw Invalid_Algorithm_Name(m_orig_algo_spec);
            }
            --level;
         }

         if(c == '/' && level > 0) {
            accum.second.push_back(c);
            expect_token = false;
         } else {
            if(expect_token) {
               throw Invalid_Algorithm_Name(m_orig_algo_spec);
            }
            if(!accum.second.empty()) {
               name.push_back(accum);
            }
            accum = std::make_pair(level, "");
            expect_token = (c != ')');
         }
      } else {
         accum.second.push_back(c);
         expect_token = false;
      }
   }

   if(!accum.second.empty()) {
      name.push_back(accum);
   }

   if(level != 0) {
      throw Invalid_Algorithm_Name(m_orig_algo_spec);
   }

   if(expect_token) {
      // A trailing separator with no following token, eg "Foo/" or "Foo,"
      throw Invalid_Algorithm_Name(m_orig_algo_spec);
   }

   if(name.empty()) {
      throw Invalid_Algorithm_Name(m_orig_algo_spec);
   }

   m_alg_name = name[0].second;

   bool in_modes = false;

   for(size_t i = 1; i != name.size(); ++i) {
      if(name[i].first == 0) {
         m_mode_info.push_back(make_arg(name, i));
         in_modes = true;
      } else if(name[i].first == 1 && !in_modes) {
         m_args.push_back(make_arg(name, i));
      }
   }
}

std::string SCAN_Name::arg(size_t i) const {
   if(i >= arg_count()) {
      throw Invalid_Argument("SCAN_Name::arg " + std::to_string(i) + " out of range for '" + to_string() + "'");
   }
   return m_args[i];
}

std::string SCAN_Name::arg(size_t i, std::string_view def_value) const {
   if(i >= arg_count()) {
      return std::string(def_value);
   }
   return m_args[i];
}

size_t SCAN_Name::arg_as_integer(size_t i, size_t def_value) const {
   if(i >= arg_count()) {
      return def_value;
   }
   return to_u32bit(m_args[i]);
}

size_t SCAN_Name::arg_as_integer(size_t i) const {
   return to_u32bit(arg(i));
}

}  // namespace Botan
/*
* Version Information
* (C) 1999-2013,2015 Jack Lloyd
*
* Botan is released under the Simplified BSD License (see license.txt)
*/



namespace Botan {

const char* short_version_cstr() {
   return BOTAN_SHORT_VERSION_STRING;
}

const char* version_cstr() {
   return BOTAN_FULL_VERSION_STRING;
}

std::string version_string() {
   return std::string(version_cstr());
}

std::string short_version_string() {
   return std::string(short_version_cstr());
}

uint32_t version_datestamp() {
   return BOTAN_VERSION_DATESTAMP;
}

std::optional<std::string> version_vc_revision() {
#if defined(BOTAN_VC_REVISION)
   return std::string(BOTAN_VC_REVISION);
#else
   return std::nullopt;
#endif
}

std::optional<std::string> version_distribution_info() {
#if defined(BOTAN_DISTRIBUTION_INFO_STRING)
   return std::string(BOTAN_DISTRIBUTION_INFO_STRING);
#else
   return std::nullopt;
#endif
}

/*
* Return parts of the version as integers
*/
uint32_t version_major() {
   return BOTAN_VERSION_MAJOR;
}

uint32_t version_minor() {
   return BOTAN_VERSION_MINOR;
}

uint32_t version_patch() {
   return BOTAN_VERSION_PATCH;
}

bool unsafe_for_production_build() {
#if defined(BOTAN_UNSAFE_FUZZER_MODE) || defined(BOTAN_TERMINATE_ON_ASSERTS)
   return true;
#else
   return false;
#endif
}

std::string runtime_version_check(uint32_t major, uint32_t minor, uint32_t patch) {
   if(major != version_major() || minor != version_minor() || patch != version_patch()) {
      return fmt("Warning: linked version ({}) does not match version built against ({}.{}.{})\n",
                 short_version_cstr(),
                 major,
                 minor,
                 patch);
   }

   return "";
}

}  // namespace Botan
