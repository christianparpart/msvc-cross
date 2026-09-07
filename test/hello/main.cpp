#include "greet.hpp"
#include <winsock2.h>
#include <cstdio>

int main()
{
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    {
        std::puts("WSAStartup failed");
        return 1;
    }
    WSACleanup();

    std::printf("%s\n", greet("windows").c_str());
    std::printf("_MSC_VER=%d __cplusplus=%ld\n", _MSC_VER, (long) __cplusplus);
    std::puts("MSVC ABI OK");
    return 0;
}
