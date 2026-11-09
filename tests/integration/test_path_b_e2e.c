/*
 * test_path_b_e2e.c -- End-to-end Path B (A12+) pipeline tests.
 *
 * These mocks exercise recovery serial writes and propagation of an
 * activation-service error. They do not establish real iBoot command
 * acceptance, code execution, a patched activation daemon, or the cause
 * of any real device's activation rejection.
 *
 * These tests therefore assert:
 *   - path_b_manipulate_identity() writes the PWND marker successfully,
 *   - when activation is rejected (simulated via
 *     mock_mobileactivation_set_activate_error), the session layer
 *     surfaces -1 cleanly and get_activation_state still says Unactivated,
 *   - signal_detect_type correctly distinguishes cellular from WiFi-only.
 *
 * The full activation pipeline is not driven here. The actual DFU to
 * recovery transition is covered separately in test_path_b_recovery.c.
 */

#include "test_framework.h"
#include "integration_helpers.h"

#include "activation/activation.h"
#include "activation/record.h"
#include "activation/session.h"
#include "bypass/path_b.h"
#include "bypass/signal.h"
#include "device/device.h"
#include "mocks/mock_control.h"

#include <libusb-1.0/libusb.h>
#include <plist/plist.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Arbitrary service error: no assertion about a real rejection cause. */
#define E2E_ACTIVATION_REJECTED (-7)

/*
 * Identity manipulation happy path.  Asserts:
 *   - path_b_manipulate_identity returns 0,
 *   - irecv_setenv("serial-number", ...) contained "PWND:[checkm8]",
 *   - irecv_saveenv was requested (persistence is not established).
 */
static void
test_path_b_e2e_identity_manipulation_succeeds(void)
{
    device_info_t dev;
    const char *current_serial =
        "CPID:8020 CPRV:11 ECID:0022334455667788";
    int rc;
    size_t i;
    int found_pwnd = 0;
    int found_saveenv = 0;

    printf("  [e2e] path_b identity manipulation (happy)\n");

    mock_reset_all();
    dev = e2e_make_device_path_b_cellular();
    dev.usb = NULL;
    dev.is_dfu_mode = 0;
    mock_irecv_set_device_info(0x1281, dev.ecid, current_serial);

    rc = path_b_manipulate_identity(&dev);
    ASSERT_EQ(rc, 0);

    for (i = 0; i < mock_get_call_count(); i++) {
        const char *line = mock_get_call_log(i);
        if (!line) continue;
        if (strstr(line, "irecv_setenv(serial-number") &&
            strstr(line, "PWND:[checkm8]"))
            found_pwnd = 1;
        if (strstr(line, "irecv_saveenv"))
            found_saveenv = 1;
    }
    ASSERT_EQ(found_pwnd,    1);
    ASSERT_EQ(found_saveenv, 1);
}

/*
 * Service rejection: simulate mobileactivation rejecting the activation
 * record, then drive the activation half of Path B directly and check
 * that session_activate returns -1, the call actually reached the
 * mobileactivation layer, and get_activation_state still says
 * "Unactivated" -- the tool must not mask the failure.
 */
static void
test_path_b_e2e_activation_rejected_by_service(void)
{
    device_info_t dev;
    plist_t record = NULL;
    plist_t session_info = NULL;
    plist_t handshake = NULL;
    char state[64];
    int rc;

    printf("  [e2e] path_b activation service rejection\n");

    mock_reset_all();
    dev = e2e_make_device_path_b_cellular();
    dev.handle   = (idevice_t)(uintptr_t)0x1;
    dev.lockdown = (lockdownd_client_t)(uintptr_t)0x2;

    /* Stage a generic rejection. This test cannot establish which
     * cryptographic checks a real phone would perform or reject. */
    mock_mobileactivation_set_activate_error(
        E2E_ACTIVATION_REJECTED);
    mock_mobileactivation_set_state("Unactivated");

    record = record_build_a12(&dev);
    ASSERT_NOTNULL(record);

    rc = session_get_info(&dev, &session_info);
    ASSERT_EQ(rc, 0);
    ASSERT_NOTNULL(session_info);

    rc = session_drm_handshake(&dev, session_info, &handshake);
    ASSERT_EQ(rc, 0);
    ASSERT_NOTNULL(handshake);

    /* Decisive assertion: with the staged service error, activation MUST
     * fail and the failure must NOT be swallowed. */
    rc = session_activate(&dev, record, handshake);
    ASSERT_EQ(rc, -1);

    ASSERT_EQ(mock_call_log_contains(
                  "mobileactivation_activate_with_session"), 1);

    rc = activation_get_state(&dev, state, sizeof(state));
    ASSERT_EQ(rc, 0);
    ASSERT_STREQ(state, "Unactivated");

    plist_free(record);
    plist_free(session_info);
    plist_free(handshake);
}

/*
 * Signal detection: cellular device (IMEI populated) -> SIGNAL_GSM,
 * WiFi-only (no IMEI, no MEID) -> SIGNAL_NONE.
 */
static void
test_path_b_e2e_signal_detection_cellular_vs_wifi(void)
{
    device_info_t dev_cell = e2e_make_device_path_b_cellular();
    device_info_t dev_wifi = e2e_make_device_path_b_wifi();
    char buf[128];
    int rc;

    printf("  [e2e] path_b signal detection (cell vs wifi)\n");

    mock_reset_all();

    ASSERT_EQ(signal_detect_type(&dev_cell), SIGNAL_GSM);
    ASSERT_EQ(signal_can_preserve(&dev_cell), 1);
    rc = signal_get_carrier_id(&dev_cell, buf, sizeof(buf));
    ASSERT_EQ(rc, 0);
    ASSERT_STREQ(buf, dev_cell.imei);

    ASSERT_EQ(signal_detect_type(&dev_wifi), SIGNAL_NONE);
    ASSERT_EQ(signal_can_preserve(&dev_wifi), 0);
    rc = signal_get_carrier_id(&dev_wifi, buf, sizeof(buf));
    ASSERT_EQ(rc, -1);
}

void
run_path_b_integration_tests(void)
{
    printf("--- Section 11: Path B end-to-end integration ---\n");
    test_path_b_e2e_identity_manipulation_succeeds();
    test_path_b_e2e_activation_rejected_by_service();
    test_path_b_e2e_signal_detection_cellular_vs_wifi();
}
