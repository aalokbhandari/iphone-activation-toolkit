/*
 * path_b.h -- Path B bypass module for A12+ devices.
 *
 * Chains: DFU -> recovery serial write -> signal detection ->
 * drmHandshake session activation -> deletescript cleanup -> verify.
 * This path does not demonstrate code execution or a patch to activation
 * validation. A serial marker alone does not establish those prerequisites.
 */

#ifndef PATH_B_H
#define PATH_B_H

#include "bypass/bypass.h"

/* The Path B bypass module for registration with bypass_register(). */
extern const bypass_module_t path_b_module;

/*
 * path_b_manipulate_identity -- Attempt a serial marker write in recovery.
 * Requires the DFU handle to be closed and is_dfu_mode cleared; validates
 * the live recovery connection via libirecovery. A marker is not proof of
 * code execution or activation. Returns 0 on success, -1 on error.
 */
int path_b_manipulate_identity(device_info_t *dev);

/*
 * path_b_read_serial -- Read a serial in DFU or validated recovery mode.
 * Copies the serial string into buf (up to len bytes including NUL).
 * Returns 0 on success, -1 on error.
 */
int path_b_read_serial(device_info_t *dev, char *buf, size_t len);

/*
 * path_b_write_serial -- Write a modified serial descriptor to the device.
 * Routes through path_b_write_serial_irecovery() which uses libirecovery
 * setenv commands from recovery mode (SET_DESCRIPTOR is rejected by A12+ BootROM).
 * Returns 0 on success, -1 on error.
 */
int path_b_write_serial(device_info_t *dev, const char *new_serial);

/*
 * path_b_write_serial_irecovery -- Write serial via iRecovery setenv in recovery mode.
 * Device must already be in recovery mode (PIDs 0x1280..0x1283).
 * Used internally by path_b.c step_manipulate_identity().
 * Returns 0 on success, -1 on error.
 */
int path_b_write_serial_irecovery(device_info_t *dev, const char *new_serial);

#endif /* PATH_B_H */
