/*
 * Placeholder for chkstk_ms.lib.
 *
 * microsip.vcxproj lists chkstk_ms.lib in the AdditionalDependencies of every
 * configuration. That archive is an ARM64-only helper that Microsoft ships
 * with the ARM64 toolchain - it does not exist for x86 or x64, so an x86/x64
 * build of MicroSIP cannot use it. MicroSIP itself is only shipped for Win32,
 * which is why upstream never hit this.
 *
 * The archive is never referenced by any symbol, it only has to *exist*,
 * otherwise the linker aborts with "cannot open input file 'chkstk_ms.lib'".
 * A single empty function is therefore enough.
 *
 * The object is compiled with /Zl (omit default library name) so that it does
 * not drag a CRT into the link: the stub has to work for both the /MTd and
 * the /MT configurations without producing an LNK4098 default library
 * conflict.
 */
int __microsip_chkstk_ms_stub(void)
{
    return 0;
}
