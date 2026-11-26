#include <feature/xbuddy_extension/xbuddy_extension.hpp>

#include <utility>

namespace buddy {

PWM255OrAuto cooling_fans_pwm = pwm_auto;
PWM255OrAuto filtration_fan_pwm = pwm_auto;

XBuddyExtension::XBuddyExtension() {
}

XBuddyExtension &xbuddy_extension() {
    static XBuddyExtension x;
    return x;
}

void XBuddyExtension::set_fan_target_pwm(Fan fan, FanPWMOrAuto pwm) {
    switch (fan) {
    case Fan::cooling_fan_1:
    case Fan::cooling_fan_2:
        cooling_fans_pwm = pwm;
        break;
    case Fan::filtration_fan:
        filtration_fan_pwm = pwm;
        break;
    }
}

bool usbpower = false;

bool XBuddyExtension::usb_power() const {
    return usbpower;
}

void XBuddyExtension::set_usb_power(bool set) {
    usbpower = set;
}

} // namespace buddy
