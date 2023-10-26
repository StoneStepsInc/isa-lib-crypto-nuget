#include <mh_sha256.h>
#include <sha256_mb.h>
#include <multi_buffer.h>

#include <cinttypes>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <memory>
#include <memory.h>
#include <stdexcept>
#include <vector>
#include <array>
#include <algorithm>

using namespace std::literals::string_literals;

// should be the same (former is defined in mh_sha256.h and the latter in sha256_mb.h)
static_assert(SHA256_DIGEST_WORDS == SHA256_DIGEST_NWORDS);

void print_hash(const char *title, size_t id, uint32_t hash[SHA256_DIGEST_WORDS])
{
   char hexhash[SHA256_DIGEST_WORDS * sizeof(uint32_t) * 2 + 1];

   static const char hex[] = "0123456789abcdef";

   // print hash bytes packed as little endian uint32_t elements
   for(size_t i = 0; i < SHA256_DIGEST_WORDS * sizeof(uint32_t); i++) {
      // reposition little endian uint32_t bytes into a byte sequence (i.e. 0th -> 3rd, 1st -> 2nd, etc)
      hexhash[((i - i % sizeof(uint32_t)) + (sizeof(uint32_t) - i % sizeof(uint32_t) - 1)) * 2] = hex[(*(reinterpret_cast<unsigned char*>(hash)+i) & 0xF0) >> 4];
      hexhash[(((i - i % sizeof(uint32_t)) + (sizeof(uint32_t) - i % sizeof(uint32_t) - 1)) * 2) + 1] = hex[*(reinterpret_cast<unsigned char*>(hash)+i) & 0x0F];
   }

   hexhash[SHA256_DIGEST_WORDS * sizeof(uint32_t) * 2] = '\x0';

   printf("%16s (%zd): %s\n", title, id, hexhash);
}

//
// A hashing function that uses the multi-hash interface, which resembles
// traditional hashing interfaces, to compute a SHA256-like hash using
// multi-buffer hashing behind the scenes.
// 
// Note that the resulting hash only resembles a SHA256 hash and will not
// compare equal to an actual SHA256 hash for the same data.
//
void compute_multihash_sha256(const std::vector<std::string>& argv)
{
   int mh_error;
   mh_sha256_ctx ctx;

   if((mh_error = mh_sha256_init(&ctx)) != MH_SHA256_CTX_ERROR_NONE)
      throw std::runtime_error(std::to_string(mh_error) + ": mh_sha256_init failed");

   for(size_t i = 0; i < argv.size(); i++) {
      if((mh_error = mh_sha256_update(&ctx, argv[i].c_str(), static_cast<uint32_t>(argv[i].length()))) != MH_SHA256_CTX_ERROR_NONE)
         throw std::runtime_error(std::to_string(mh_error) + ": mh_sha256_update failed");
   }

   uint32_t hash[SHA256_DIGEST_WORDS];

   if((mh_error = mh_sha256_finalize(&ctx, hash)) != MH_SHA256_CTX_ERROR_NONE)
      throw std::runtime_error(std::to_string(mh_error) + ": mh_sha256_finalize failed");

   print_hash("Multi-hash", 0, hash);

}

//
// A hashing function for multiple data sequences being hashed
// in parallel by the underlying hash context manager.
//
void compute_multibuffer_sha256(const std::vector<std::string>& argv1, const std::vector<std::string>& argv2)
{
   // data processing context tracking progress within a hashing context
   struct argv_ctx_t {
      const std::vector<std::string> *argv;  // input data sequence
      size_t processed;                      // number of processed data items
      size_t id;                             // context identifier for reporting purposes
   };

   std::array<argv_ctx_t, 2> argv_ctxs = {argv_ctx_t{&argv1, 0, 0}, argv_ctx_t{&argv2, 0, 0}};

   std::array<SHA256_HASH_CTX, argv_ctxs.size()> mb_ctx;
   SHA256_HASH_CTX *mb_ctx_ptr = nullptr;
   size_t ctx_in_use = 0;

   SHA256_HASH_CTX_MGR ctx_mgr;

   sha256_ctx_mgr_init(&ctx_mgr);

   //
   // Set up a hashing context for each data sequence we want to hash
   // and wire each context to point to the data processing context, so
   // we can access the data from continuation contexts returned by the
   // hash context manager.
   //
   for(size_t i = 0; i < argv_ctxs.size(); i++) {
      // sets mb_ctx[i].status to HASH_CTX_STS_COMPLETE
      hash_ctx_init(&mb_ctx[i]);

      // just store the index for reporting purposes
      argv_ctxs[i].id = i;

      // store a pointer to the corresponding data context
      mb_ctx[i].user_data = &argv_ctxs[i];
   }

   //
   // This is a simplified loop using 2 contexts for 2 data sequences.
   // Actual applications may use 4 or 8 (AVX2) or 16 (AVX512) contexts
   // to process unlimited number of jobs, submitting a new one when
   // one of the earlier ones is completed.
   // 
   // Note that a hashing context returned from any submit call may be
   // different from the one passed in as an argument. Those that are
   // not completed should be updated with more data from their data
   // sequence and completed ones can be used to start a new hashing
   // job or can be ignored if there is no more data.
   //
   while ((argv_ctxs[0].processed + argv_ctxs[1].processed) < (argv1.size() + argv2.size())) {
      if(mb_ctx_ptr) {
         argv_ctx_t *argv_ctx = reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data);

         if(argv_ctx->processed == argv_ctx->argv->size()) {
            //
            // This will happen if one of the data sequences has one item
            // and the other has more, so the loop keeps going after
            // HASH_FIRST was submitted for the former, and since there's
            // no more data, we end it with a zero-sized HASH_LAST (see
            // the final flush loop for more).
            // 
            // In actual applications, the logic should be consistent when
            // starting and updating jobs and if the underlying data sequence
            // allows to detect the last chunk of data, HASH_ENTIRE should
            // be used for a single data item when starting a job, which
            // would eliminate the need for this code.
            //
            mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, nullptr, 0, HASH_LAST);
         }
         else {
            mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, (*argv_ctx->argv)[argv_ctx->processed].c_str(), static_cast<uint32_t>((*argv_ctx->argv)[argv_ctx->processed].length()), argv_ctx->processed == argv_ctx->argv->size()-1 ? HASH_LAST : HASH_UPDATE);
            argv_ctx->processed++;
         }
      }
      else if(ctx_in_use < argv_ctxs.size()) {
         argv_ctx_t *argv_ctx = reinterpret_cast<argv_ctx_t*>(mb_ctx[ctx_in_use].user_data);

         // only first data block can start a job
         if(argv_ctx->processed != 0)
            throw std::runtime_error("Cannot start a job for partially-processed data for " + std::to_string(argv_ctx->id));

         mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, &mb_ctx[ctx_in_use], (*argv_ctx->argv)[argv_ctx->processed].c_str(), static_cast<uint32_t>((*argv_ctx->argv)[argv_ctx->processed].length()), HASH_FIRST);
         argv_ctx->processed++;
         ctx_in_use++;
      }
      else {
         if((mb_ctx_ptr = sha256_ctx_mgr_flush(&ctx_mgr)) == nullptr)
            throw std::runtime_error("sha256_ctx_mgr_flush failed");
      }

      if(mb_ctx_ptr) {
         if(mb_ctx_ptr->error != HASH_CTX_ERROR_NONE)
            throw std::runtime_error(std::to_string(mb_ctx_ptr->error) + ": got a context with an error for " + std::to_string(reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data)->id));

         //
         // We may arrive here either after flushing or, according to the
         // docs, after HASH_LAST was submitted, which was never observed
         // in testing.
         // 
         // Note that the HASH_CTX_STS_COMPLETE bit may be combined with
         // HASH_CTX_STS_PROCESSING for contexts that are still being
         // processed. Bitwise test should never be used to check if the
         // job is complete (see hash_ctx_complete macro in multi_buffer.h).
         //
         if(mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE) {
            print_hash("Multi-buffer", reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data)->id, mb_ctx_ptr->job.result_digest);

            //
            // For a more complex workflow, we could pass the context along
            // and check whether the job was completed in conditions above,
            // so it would end up in the block submitting HASH_FIRST, which
            // would submit a new job for a pending data sequence.
            //
            mb_ctx_ptr = nullptr;
         }
      }
   }

   //
   // Finalize active jobs. Given the logic above, we should end up here
   // with jobs that only have HASH_FIRST submitted or have HASH_LAST
   // submitted, but not finalized yet because of other jobs. In actual
   // applications, it will be harder to detect the last data sequence
   // (e.g. a network read may be less than requested without it being
   // the end of data), some some contexts will have only HASH_UPDATE
   // submitted and will need HASH_LAST submitted in this loop as well.
   //
   while((mb_ctx_ptr = sha256_ctx_mgr_flush(&ctx_mgr)) != nullptr) {
      argv_ctx_t *argv_ctx = reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data);

      if(mb_ctx_ptr->error != HASH_CTX_ERROR_NONE)
         throw std::runtime_error(std::to_string(mb_ctx_ptr->error) + ": get flush the context");

      if(mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE)
         print_hash("Multi-buffer", reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data)->id, mb_ctx_ptr->job.result_digest);
      else {
         // we should only end up here for jobs with multiple sub-sequences
         if(argv_ctx->argv->size() != 1)
            throw std::runtime_error("Bad job state for " + std::to_string(argv_ctx->id));

         //
         // This will happen if there was just one buffer for this job and
         // other larger jobs didn't force it to submit a zero-length update,
         // so only HASH_FIRST was submitted. Docs allow calling HASH_LAST
         // with a zero-sized buffer (nullptr isn't mentioned, though), even
         // though a more optimal approach is to call HASH_ENTIRE instead of
         // HASH_FIRST when it is known that there is no more data for some
         // sequence.
         //
         mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, nullptr, 0, HASH_LAST);

         if(mb_ctx_ptr && mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE)
            print_hash("Multi-buffer", reinterpret_cast<argv_ctx_t*>(mb_ctx_ptr->user_data)->id, mb_ctx_ptr->job.result_digest);
      }
   }
}

//
// A hashing function for a single data sequence with blocks resembling
// traditional hashing interfaces.
//
void compute_multibuffer_sha256(const std::vector<std::string>& argv)
{
   //
   // init
   //

   SHA256_HASH_CTX mb_ctx, *mb_ctx_ptr = nullptr;

   SHA256_HASH_CTX_MGR ctx_mgr;

   sha256_ctx_mgr_init(&ctx_mgr);

   hash_ctx_init(&mb_ctx);

   // user data is unintialized in the macro above
   mb_ctx.user_data = nullptr;

   //
   // 1st update
   //

   mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, &mb_ctx, argv[0].c_str(), static_cast<uint32_t>(argv[0].length()), HASH_FIRST);

   size_t processed = 1;

   //
   // Nth update
   //

   // we don't call HASH_LAST in the loop, so jobs will never be completed within the loop
   while(processed != argv.size()) {
      if(mb_ctx_ptr) {
         // this shouldn't happen for a single job because we exit the loop after the last item
         if(processed == argv.size())
            throw std::runtime_error("Attempting to hash past available data");

         mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, argv[processed].c_str(), static_cast<uint32_t>(argv[processed].length()), HASH_UPDATE);

         processed++;
      }
      else {
         if((mb_ctx_ptr = sha256_ctx_mgr_flush(&ctx_mgr)) == nullptr)
            throw std::runtime_error("sha256_ctx_mgr_flush failed");
      }

      if(mb_ctx_ptr && mb_ctx_ptr->error != HASH_CTX_ERROR_NONE)
         throw std::runtime_error(std::to_string(mb_ctx_ptr->error) + ": got a context with an error");
   }

   //
   // finalize
   //

   if(mb_ctx_ptr) {
      // this runs for short input (e.g. ABC), which returns a context after HASH_FIRST
      mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, nullptr, 0, HASH_LAST);

      // should be no other flags at this point - use ==
      if(mb_ctx_ptr && mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE)
         // this was never observed in testing
         print_hash("Multi-buffer", 0, mb_ctx_ptr->job.result_digest);
   }

   while((mb_ctx_ptr = sha256_ctx_mgr_flush(&ctx_mgr)) != nullptr) {
      if(mb_ctx_ptr->error != HASH_CTX_ERROR_NONE)
         throw std::runtime_error(std::to_string(mb_ctx_ptr->error) + ": sha256_ctx_mgr_flush failed");

      // should be no other flags at this point - use ==
      if(mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE)
         print_hash("Multi-buffer", 0, mb_ctx_ptr->job.result_digest);
      else {
         // this runs for long input (e.g. 30 A's, one sequence), after HASH_FIRST returns NULL
         mb_ctx_ptr = sha256_ctx_mgr_submit(&ctx_mgr, mb_ctx_ptr, nullptr, 0, HASH_LAST);

         if(mb_ctx_ptr && mb_ctx_ptr->status == HASH_CTX_STS_COMPLETE)
            print_hash("Multi-buffer", 0, mb_ctx_ptr->job.result_digest);
      }
   }
}

int main(int argc, char *argv[])
{
   if(argc < 2) {
      printf("Usage: sample-isa-lib-crypto text-to-hash [... text-to-hash]\n");
      return EXIT_FAILURE;
   }

   std::vector<std::string> argv1, argv2;

   for(size_t i = 1; i < argc; i++) {
      argv1.push_back(argv[i]);
      argv2.push_back(argv[i]);
   }

   std::reverse(argv2.begin(), argv2.end());

   // make the second vector longer, to make the hashing loop dynamic more realistic
   argv2.insert(argv2.end(), argv1.begin(), argv1.end());

   try {
      // print both inputs
      printf("\n%d: ", 0);
      for(const std::string& str : argv1)
         fputs(str.c_str(), stdout);
      fputs("\n", stdout);

      printf("\n%d: ", 1);
      for(const std::string& str : argv2)
         fputs(str.c_str(), stdout);
      fputs("\n\n", stdout);

      compute_multihash_sha256(argv1);

      fputc('\n', stdout);

      // compute multibuffer SHA256 of both arguments in parallel
      compute_multibuffer_sha256(argv1, argv2);

      fputc('\n', stdout);

      // compute multibuffer SHA256 of just the first argument
      compute_multibuffer_sha256(argv1);

      fputc('\n', stdout);

      return EXIT_SUCCESS;
   }
   catch (const std::exception& error) {
      printf("ERROR (std): %s\n", error.what());
   }
   catch (...) {
      printf("ERROR (unknown)\n");
   }

   return EXIT_FAILURE;   
}
