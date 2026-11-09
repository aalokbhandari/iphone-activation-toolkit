/* Recovery transport regressions; these do not establish an activation bypass. */
#include "test_framework.h"
#include "bypass/path_b.h"
#include "mocks/mock_control.h"

#include <libirecovery.h>
#include <stdint.h>
#include <string.h>

static device_info_t recovery_device(void)
{
    device_info_t dev;
    memset(&dev, 0, sizeof(dev));
    dev.ecid = UINT64_C(0x0022334455667788);
    return dev;
}

/* Drive the real transition, then deliberately stop at the serial write.
 * The failure return alone cannot distinguish the old NULL-DFU-handle
 * rejection from reaching iRecovery, so assert the transport calls too. */
static void test_dfu_to_recovery_reaches_identity_write(void)
{
    device_info_t dev = recovery_device();
    int modes[] = { IRECV_K_RECOVERY_MODE_1, IRECV_K_RECOVERY_MODE_2,
                    IRECV_K_RECOVERY_MODE_3, IRECV_K_RECOVERY_MODE_4 };
    int sentinel;
    int rc;
    size_t i;

    for (i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        mock_reset_all();
        dev.usb = (libusb_device_handle *)&sentinel;
        dev.is_dfu_mode = 1;
        mock_libusb_set_device_list(1, 0x05ac, (uint16_t)modes[i]);
        mock_irecv_set_device_info(modes[i], dev.ecid,
                                  "CPID:8020 ECID:0022334455667788");
        mock_irecv_set_setenv_result("serial-number", IRECV_E_UNKNOWN_ERROR);

        rc = path_b_module.execute(&dev);

        ASSERT_EQ(rc, -1);
        ASSERT_NULL(dev.usb);
        ASSERT_EQ(dev.is_dfu_mode, 0);
        ASSERT_EQ(mock_call_log_contains("req=0x06"), 1);
        ASSERT_EQ(mock_call_log_contains("usb_dfu_close"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_get_mode"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_get_device_info"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_setenv(serial-number="), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_reboot"), 0);
        ASSERT_EQ(mock_call_log_contains("mobileactivation_"), 0);
    }
}

static void test_recovery_without_dfu_handle(void)
{
    device_info_t dev = recovery_device();
    int modes[] = { IRECV_K_RECOVERY_MODE_1, IRECV_K_RECOVERY_MODE_2,
                    IRECV_K_RECOVERY_MODE_3, IRECV_K_RECOVERY_MODE_4 };
    size_t i;

    for (i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        mock_reset_all();
        /* An existing marker exercises the early-return branch as well:
         * it must still validate the live recovery connection first. */
        mock_irecv_set_device_info(modes[i], dev.ecid,
                                  "CPID:8020 PWND:[checkm8]");
        ASSERT_EQ(path_b_manipulate_identity(&dev), 0);
        ASSERT_EQ(mock_call_log_contains("irecv_get_mode"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_close"), 1);
        ASSERT_EQ(mock_call_log_contains("libusb_control_transfer"), 0);
        ASSERT_EQ(mock_call_log_contains("irecv_setenv"), 0);
    }
}

static void test_invalid_recovery_connections(void)
{
    device_info_t dev = recovery_device();
    int modes[] = { IRECV_K_DFU_MODE, 0x12a8 };
    size_t i;

    for (i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        mock_reset_all();
        mock_irecv_set_device_info(modes[i], dev.ecid,
                                  "CPID:8020 PWND:[checkm8]");
        ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
        ASSERT_EQ(mock_call_log_contains("irecv_get_mode"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_close"), 1);
        ASSERT_EQ(mock_call_log_contains("irecv_setenv"), 0);
    }

    mock_reset_all();
    mock_irecv_set_open_error(IRECV_E_NO_DEVICE);
    ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
    ASSERT_EQ(mock_call_log_contains("irecv_open_with_ecid"), 1);
    ASSERT_EQ(mock_call_log_contains("irecv_setenv"), 0);

    mock_reset_all();
    mock_irecv_set_device_info(IRECV_K_RECOVERY_MODE_2, dev.ecid, "");
    ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
    ASSERT_EQ(mock_call_log_contains("irecv_close"), 1);
    ASSERT_EQ(mock_call_log_contains("irecv_setenv"), 0);
}

static void test_recovery_serial_write_and_readback(void)
{
    device_info_t dev = recovery_device();
    char serial[128];

    mock_reset_all();
    mock_irecv_set_device_info(IRECV_K_RECOVERY_MODE_2, dev.ecid,
                              "CPID:8020 ECID:0022334455667788");
    ASSERT_EQ(path_b_manipulate_identity(&dev), 0);
    ASSERT_EQ(path_b_read_serial(&dev, serial, sizeof(serial)), 0);
    ASSERT_STREQ(serial, "CPID:8020 ECID:0022334455667788 PWND:[checkm8]");
    ASSERT_EQ(mock_call_log_contains("irecv_saveenv"), 1);
    ASSERT_EQ(mock_call_log_contains("libusb_control_transfer"), 0);
    ASSERT_NULL(dev.usb);
    ASSERT_EQ(dev.is_dfu_mode, 0);
}

static void test_failed_readback_does_not_report_success(void)
{
    device_info_t dev = recovery_device();

    mock_reset_all();
    mock_irecv_set_device_info(IRECV_K_RECOVERY_MODE_2, dev.ecid,
                              "CPID:8020 ECID:0022334455667788");
    mock_irecv_queue_open_result(0); /* initial serial read */
    mock_irecv_queue_open_result(0); /* serial write */
    mock_irecv_queue_open_result(IRECV_E_NO_DEVICE); /* verification read */
    ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
    ASSERT_EQ(mock_call_log_contains("irecv_setenv(serial-number="), 1);
    ASSERT_EQ(mock_call_log_contains("irecv_saveenv"), 1);
}

static void test_dfu_state_requires_transition(void)
{
    device_info_t dev = recovery_device();
    int sentinel;

    mock_reset_all();
    ASSERT_EQ(path_b_manipulate_identity(NULL), -1);
    dev.is_dfu_mode = 1;
    ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
    dev.is_dfu_mode = 0;
    dev.usb = (libusb_device_handle *)&sentinel;
    ASSERT_EQ(path_b_manipulate_identity(&dev), -1);
    ASSERT_EQ(mock_call_log_contains("libusb_control_transfer"), 0);
    ASSERT_EQ(mock_call_log_contains("irecv_setenv"), 0);
}

void run_path_b_recovery_tests(void)
{
    printf("--- Path B recovery transport regressions ---\n");
    test_dfu_to_recovery_reaches_identity_write();
    test_recovery_without_dfu_handle();
    test_invalid_recovery_connections();
    test_recovery_serial_write_and_readback();
    test_failed_readback_does_not_report_success();
    test_dfu_state_requires_transition();
}
