#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <string.h>

/* TO BUILD: gcc -lcrypto -g crypto_sample.c
             ./a.out
*/

void printhex(unsigned char * hex, int len); 

/*
 * Encrypt "plaintext_in" with "key" into "ciphertext"
 * "ciphertext" must be a char[] with enough space to hold the output
 * Uses IV of all zeroes
 *
 * Returns the length of "ciphertext" or -1 on error
 */
int encrypt(unsigned char *plaintext_in, int plaintext_len, unsigned char *key, 
        unsigned char *ciphertext) {
    EVP_CIPHER_CTX *ctx;
    unsigned char iv[16] = {0};
    int len = 0;
    int ciphertext_len = 0;

    if(!(ctx = EVP_CIPHER_CTX_new())) {
        return -1;
    }
    if(EVP_EncryptInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv) != 1) {
        return -1;
    }
    if(EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext_in, plaintext_len) != 1) {
        return -1;
    }
    ciphertext_len = len;

    if(EVP_EncryptFinal_ex(ctx, ciphertext + len, &len) != 1) {
        return -1;
    }
    ciphertext_len += len;

    /* Clean up */
    EVP_CIPHER_CTX_free(ctx);

    return ciphertext_len;
}

/*
 * Decrypt "cipher" with "key" into "plain"
 */
int decrypt(unsigned char *ciphertext, int ciphertext_len, unsigned char *key,
        unsigned char *plaintext) {
    EVP_CIPHER_CTX *ctx;
    unsigned char iv[16] = {0};
    int len;
    int plaintext_len;

    if(!(ctx = EVP_CIPHER_CTX_new())) {
        return -1;
    }
    if(EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv) != 1) {
        return -1;
    }
    if(EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, ciphertext_len) != 1) {
        return -1; 
    }
    plaintext_len = len;
    if(EVP_DecryptFinal_ex(ctx, plaintext + len, &len) != 1) {
        return -1; 
    }
    plaintext_len += len;

    /* Clean up */
    EVP_CIPHER_CTX_free(ctx);

    return plaintext_len;
}

/*
 * Sign "cipher" with "key"
 */
int sign(const unsigned char* key, unsigned char* cipher, int cipher_len, 
        unsigned char* tag) {
    int len = 0;
    HMAC_CTX ctx;

    HMAC_CTX_init(&ctx);
    HMAC_Init_ex(&ctx, key, strlen(key), EVP_sha1(), NULL);
    HMAC_Update(&ctx, cipher, cipher_len);
    HMAC_Final(&ctx, tag, &len);
    
    HMAC_CTX_cleanup(&ctx);
    return len;
}

/*
 * Debugging purposes only
 */
void printhex(unsigned char * hex, int len) {
    int i;
    if (hex == NULL) return;
    for (i = 0; i < len; i++) {
        printf("%02x ", hex[i]);
    }
    printf("\n");
}

int main() {
    unsigned char m[] = "This is a secret";
    unsigned char * key = "1234567890123456";
    unsigned char cipher[128] = {0};
    unsigned char iv[16] = {0};
    unsigned char plain[128] = {0};
    unsigned char tag[128] = {0};


    int cipher_len = encrypt(m, strlen(m)+1, key, cipher);
    printf("ciphertext length: %d\nciphertext: ", cipher_len);
    printhex(cipher, cipher_len);
    int plain_len = decrypt(cipher, cipher_len, key, plain);
    printf("plaintext length: %d\nplaintext: ", plain_len);
    printf("%s\n", plain);

    int tag_len = sign(key, m, strlen(m) + 1, tag);
    printf("tag length: %d\ntag: ", tag_len);
    printhex(tag, tag_len);
}