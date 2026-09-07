#include "greet.hpp"
#include <format>
std::string greet(std::string_view who)
{
    return std::format("hello, {}", who);
}
