#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# NumLock repair extracted from xiaoMGitHub/LEGION_Y7000Series_Hackintosh_Fix.
# Original setleds credits Damien Guard and Rajitha Perera.
# Source snapshot https://github.com/xiaoMGitHub/LEGION_Y7000Series_Hackintosh_Fix/tree/064b9a1547c36f4241f6d313f5d810a1d6c7cc80
# setleds source https://github.com/rajiteh/setledsmac
# Embedded executable is the unmodified x86_64 executable from that snapshot.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LABEL=com.rajiteh.setleds
BIN=/usr/local/bin/setleds
PLIST=/Library/LaunchDaemons/com.rajiteh.setleds.plist
EXPECTED=0ffca24e4668fe476a7a79e53bed5e48841928f635e931f67ee2e22f0a9a1966
ACTION=${1:-install}
case "$ACTION" in
    install|uninstall|status|restart) ;;
    *) echo '用法：bash numlock-fix-macos26.command [install|status|restart|uninstall]'; exit 2 ;;
esac
[ "$(uname -s)" = Darwin ] || { echo '此脚本需要 macOS。'; exit 1; }
if [ "$ACTION" = install ] || [ "$ACTION" = restart ]; then
    [ "$(uname -m)" = x86_64 ] || { echo '此版本适用于 Intel 黑苹果电脑。'; exit 1; }
fi
if [ "$ACTION" = status ]; then
    launchctl print "system/$LABEL" || true
    echo '已安装文件：'
    ls -l "$BIN" "$PLIST" 2>/dev/null || true
    echo '最近日志：'
    tail -n 25 /var/log/numlock-fix.log 2>/dev/null || true
    exit 0
fi
if [ "$EUID" -ne 0 ]; then
    exec /usr/bin/sudo /bin/bash "$0" "$ACTION"
fi
if [ "$ACTION" = uninstall ]; then
    if launchctl print "system/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "system/$LABEL"
    fi
    rm -f "$PLIST" "$BIN"
    echo '数字小键盘修复已卸载。'
    exit
fi
TMP_DIR=$(mktemp -d /private/tmp/numlock-fix.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT
# Read the payload without executing it.
sed -n '/^__NUMLOCK_PAYLOAD__$/,$p' "$0" | sed '1d' | base64 -D > "$TMP_DIR/setleds"
ACTUAL=$(shasum -a 256 "$TMP_DIR/setleds")
[ "${ACTUAL%% *}" = "$EXPECTED" ] || { echo '内置程序校验失败，请重新下载脚本。'; exit 1; }
cat > "$TMP_DIR/service.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.rajiteh.setleds</string>
<key>ProgramArguments</key><array><string>/usr/local/bin/setleds</string><string>monitor</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>StandardOutPath</key><string>/var/log/numlock-fix.log</string>
<key>StandardErrorPath</key><string>/var/log/numlock-fix.log</string>
</dict></plist>
PLIST
plutil -lint "$TMP_DIR/service.plist"
# Keep the previous installation for rollback if registration fails.
WAS_LOADED=0
[ ! -e "$BIN" ] || cp -p "$BIN" "$TMP_DIR/old-bin"
[ ! -e "$PLIST" ] || cp -p "$PLIST" "$TMP_DIR/old-plist"
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    WAS_LOADED=1
    launchctl bootout "system/$LABEL"
fi
rollback() {
    launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
    rm -f "$BIN" "$PLIST"
    [ ! -e "$TMP_DIR/old-bin" ] || cp -p "$TMP_DIR/old-bin" "$BIN"
    [ ! -e "$TMP_DIR/old-plist" ] || cp -p "$TMP_DIR/old-plist" "$PLIST"
    if [ "$WAS_LOADED" = 1 ] && [ -e "$PLIST" ]; then
        launchctl bootstrap system "$PLIST" || true
    fi
    echo '安装失败，已尝试恢复原有文件。' >&2
}
trap 'rollback' ERR
install -d -o root -g wheel -m 755 /usr/local/bin
# Preserve an existing identical executable and its privacy permission identity.
if [ ! -f "$BIN" ] || ! cmp -s "$TMP_DIR/setleds" "$BIN"; then
    install -o root -g wheel -m 755 "$TMP_DIR/setleds" "$BIN"
else
    chown root:wheel "$BIN"
    chmod 755 "$BIN"
fi
install -o root -g wheel -m 644 "$TMP_DIR/service.plist" "$PLIST"
launchctl enable "system/$LABEL"
launchctl bootstrap system "$PLIST"
launchctl kickstart -k "system/$LABEL"
sleep 3
SERVICE_STATUS=$(launchctl print "system/$LABEL")
if ! printf '%s\n' "$SERVICE_STATUS" | /usr/bin/grep -q 'state = running'; then
    # Event tap creation failure may be caused by privacy permissions. Keep the executable at its stable path
    # so the user can grant macOS privacy permissions to that exact file.
    trap - ERR
    launchctl bootout "system/$LABEL" || true
    echo '监听尚未启动。安装文件已保留，服务已停止。'
    tail -n 15 /var/log/numlock-fix.log || true
    echo
    echo '请在 系统设置 → 隐私与安全 → 辅助功能 中添加并启用：'
    echo '    /usr/local/bin/setleds'
    echo '再在 输入监控 中添加并启用同一程序。'
    echo '添加窗口可按 Command+Shift+G，粘贴上述完整路径。'
    echo '完成授权后，重新运行此脚本。无需重启电脑。'
    echo '若已授权仍失败，请运行此脚本的 status 操作并提供输出。'
    exit 3
fi
trap - ERR
echo 'monitor 监听进程已启动，开机自动启动。'
echo '请测试数字键及睡眠唤醒后的输入。日志位于 /var/log/numlock-fix.log。'
exit 0

#                     GNU GENERAL PUBLIC LICENSE
#                        Version 3, 29 June 2007
# 
#  Copyright (C) 2007 Free Software Foundation, Inc. <http://fsf.org/>
#  Everyone is permitted to copy and distribute verbatim copies
#  of this license document, but changing it is not allowed.
# 
#                             Preamble
# 
#   The GNU General Public License is a free, copyleft license for
# software and other kinds of works.
# 
#   The licenses for most software and other practical works are designed
# to take away your freedom to share and change the works.  By contrast,
# the GNU General Public License is intended to guarantee your freedom to
# share and change all versions of a program--to make sure it remains free
# software for all its users.  We, the Free Software Foundation, use the
# GNU General Public License for most of our software; it applies also to
# any other work released this way by its authors.  You can apply it to
# your programs, too.
# 
#   When we speak of free software, we are referring to freedom, not
# price.  Our General Public Licenses are designed to make sure that you
# have the freedom to distribute copies of free software (and charge for
# them if you wish), that you receive source code or can get it if you
# want it, that you can change the software or use pieces of it in new
# free programs, and that you know you can do these things.
# 
#   To protect your rights, we need to prevent others from denying you
# these rights or asking you to surrender the rights.  Therefore, you have
# certain responsibilities if you distribute copies of the software, or if
# you modify it: responsibilities to respect the freedom of others.
# 
#   For example, if you distribute copies of such a program, whether
# gratis or for a fee, you must pass on to the recipients the same
# freedoms that you received.  You must make sure that they, too, receive
# or can get the source code.  And you must show them these terms so they
# know their rights.
# 
#   Developers that use the GNU GPL protect your rights with two steps:
# (1) assert copyright on the software, and (2) offer you this License
# giving you legal permission to copy, distribute and/or modify it.
# 
#   For the developers' and authors' protection, the GPL clearly explains
# that there is no warranty for this free software.  For both users' and
# authors' sake, the GPL requires that modified versions be marked as
# changed, so that their problems will not be attributed erroneously to
# authors of previous versions.
# 
#   Some devices are designed to deny users access to install or run
# modified versions of the software inside them, although the manufacturer
# can do so.  This is fundamentally incompatible with the aim of
# protecting users' freedom to change the software.  The systematic
# pattern of such abuse occurs in the area of products for individuals to
# use, which is precisely where it is most unacceptable.  Therefore, we
# have designed this version of the GPL to prohibit the practice for those
# products.  If such problems arise substantially in other domains, we
# stand ready to extend this provision to those domains in future versions
# of the GPL, as needed to protect the freedom of users.
# 
#   Finally, every program is threatened constantly by software patents.
# States should not allow patents to restrict development and use of
# software on general-purpose computers, but in those that do, we wish to
# avoid the special danger that patents applied to a free program could
# make it effectively proprietary.  To prevent this, the GPL assures that
# patents cannot be used to render the program non-free.
# 
#   The precise terms and conditions for copying, distribution and
# modification follow.
# 
#                        TERMS AND CONDITIONS
# 
#   0. Definitions.
# 
#   "This License" refers to version 3 of the GNU General Public License.
# 
#   "Copyright" also means copyright-like laws that apply to other kinds of
# works, such as semiconductor masks.
# 
#   "The Program" refers to any copyrightable work licensed under this
# License.  Each licensee is addressed as "you".  "Licensees" and
# "recipients" may be individuals or organizations.
# 
#   To "modify" a work means to copy from or adapt all or part of the work
# in a fashion requiring copyright permission, other than the making of an
# exact copy.  The resulting work is called a "modified version" of the
# earlier work or a work "based on" the earlier work.
# 
#   A "covered work" means either the unmodified Program or a work based
# on the Program.
# 
#   To "propagate" a work means to do anything with it that, without
# permission, would make you directly or secondarily liable for
# infringement under applicable copyright law, except executing it on a
# computer or modifying a private copy.  Propagation includes copying,
# distribution (with or without modification), making available to the
# public, and in some countries other activities as well.
# 
#   To "convey" a work means any kind of propagation that enables other
# parties to make or receive copies.  Mere interaction with a user through
# a computer network, with no transfer of a copy, is not conveying.
# 
#   An interactive user interface displays "Appropriate Legal Notices"
# to the extent that it includes a convenient and prominently visible
# feature that (1) displays an appropriate copyright notice, and (2)
# tells the user that there is no warranty for the work (except to the
# extent that warranties are provided), that licensees may convey the
# work under this License, and how to view a copy of this License.  If
# the interface presents a list of user commands or options, such as a
# menu, a prominent item in the list meets this criterion.
# 
#   1. Source Code.
# 
#   The "source code" for a work means the preferred form of the work
# for making modifications to it.  "Object code" means any non-source
# form of a work.
# 
#   A "Standard Interface" means an interface that either is an official
# standard defined by a recognized standards body, or, in the case of
# interfaces specified for a particular programming language, one that
# is widely used among developers working in that language.
# 
#   The "System Libraries" of an executable work include anything, other
# than the work as a whole, that (a) is included in the normal form of
# packaging a Major Component, but which is not part of that Major
# Component, and (b) serves only to enable use of the work with that
# Major Component, or to implement a Standard Interface for which an
# implementation is available to the public in source code form.  A
# "Major Component", in this context, means a major essential component
# (kernel, window system, and so on) of the specific operating system
# (if any) on which the executable work runs, or a compiler used to
# produce the work, or an object code interpreter used to run it.
# 
#   The "Corresponding Source" for a work in object code form means all
# the source code needed to generate, install, and (for an executable
# work) run the object code and to modify the work, including scripts to
# control those activities.  However, it does not include the work's
# System Libraries, or general-purpose tools or generally available free
# programs which are used unmodified in performing those activities but
# which are not part of the work.  For example, Corresponding Source
# includes interface definition files associated with source files for
# the work, and the source code for shared libraries and dynamically
# linked subprograms that the work is specifically designed to require,
# such as by intimate data communication or control flow between those
# subprograms and other parts of the work.
# 
#   The Corresponding Source need not include anything that users
# can regenerate automatically from other parts of the Corresponding
# Source.
# 
#   The Corresponding Source for a work in source code form is that
# same work.
# 
#   2. Basic Permissions.
# 
#   All rights granted under this License are granted for the term of
# copyright on the Program, and are irrevocable provided the stated
# conditions are met.  This License explicitly affirms your unlimited
# permission to run the unmodified Program.  The output from running a
# covered work is covered by this License only if the output, given its
# content, constitutes a covered work.  This License acknowledges your
# rights of fair use or other equivalent, as provided by copyright law.
# 
#   You may make, run and propagate covered works that you do not
# convey, without conditions so long as your license otherwise remains
# in force.  You may convey covered works to others for the sole purpose
# of having them make modifications exclusively for you, or provide you
# with facilities for running those works, provided that you comply with
# the terms of this License in conveying all material for which you do
# not control copyright.  Those thus making or running the covered works
# for you must do so exclusively on your behalf, under your direction
# and control, on terms that prohibit them from making any copies of
# your copyrighted material outside their relationship with you.
# 
#   Conveying under any other circumstances is permitted solely under
# the conditions stated below.  Sublicensing is not allowed; section 10
# makes it unnecessary.
# 
#   3. Protecting Users' Legal Rights From Anti-Circumvention Law.
# 
#   No covered work shall be deemed part of an effective technological
# measure under any applicable law fulfilling obligations under article
# 11 of the WIPO copyright treaty adopted on 20 December 1996, or
# similar laws prohibiting or restricting circumvention of such
# measures.
# 
#   When you convey a covered work, you waive any legal power to forbid
# circumvention of technological measures to the extent such circumvention
# is effected by exercising rights under this License with respect to
# the covered work, and you disclaim any intention to limit operation or
# modification of the work as a means of enforcing, against the work's
# users, your or third parties' legal rights to forbid circumvention of
# technological measures.
# 
#   4. Conveying Verbatim Copies.
# 
#   You may convey verbatim copies of the Program's source code as you
# receive it, in any medium, provided that you conspicuously and
# appropriately publish on each copy an appropriate copyright notice;
# keep intact all notices stating that this License and any
# non-permissive terms added in accord with section 7 apply to the code;
# keep intact all notices of the absence of any warranty; and give all
# recipients a copy of this License along with the Program.
# 
#   You may charge any price or no price for each copy that you convey,
# and you may offer support or warranty protection for a fee.
# 
#   5. Conveying Modified Source Versions.
# 
#   You may convey a work based on the Program, or the modifications to
# produce it from the Program, in the form of source code under the
# terms of section 4, provided that you also meet all of these conditions:
# 
#     a) The work must carry prominent notices stating that you modified
#     it, and giving a relevant date.
# 
#     b) The work must carry prominent notices stating that it is
#     released under this License and any conditions added under section
#     7.  This requirement modifies the requirement in section 4 to
#     "keep intact all notices".
# 
#     c) You must license the entire work, as a whole, under this
#     License to anyone who comes into possession of a copy.  This
#     License will therefore apply, along with any applicable section 7
#     additional terms, to the whole of the work, and all its parts,
#     regardless of how they are packaged.  This License gives no
#     permission to license the work in any other way, but it does not
#     invalidate such permission if you have separately received it.
# 
#     d) If the work has interactive user interfaces, each must display
#     Appropriate Legal Notices; however, if the Program has interactive
#     interfaces that do not display Appropriate Legal Notices, your
#     work need not make them do so.
# 
#   A compilation of a covered work with other separate and independent
# works, which are not by their nature extensions of the covered work,
# and which are not combined with it such as to form a larger program,
# in or on a volume of a storage or distribution medium, is called an
# "aggregate" if the compilation and its resulting copyright are not
# used to limit the access or legal rights of the compilation's users
# beyond what the individual works permit.  Inclusion of a covered work
# in an aggregate does not cause this License to apply to the other
# parts of the aggregate.
# 
#   6. Conveying Non-Source Forms.
# 
#   You may convey a covered work in object code form under the terms
# of sections 4 and 5, provided that you also convey the
# machine-readable Corresponding Source under the terms of this License,
# in one of these ways:
# 
#     a) Convey the object code in, or embodied in, a physical product
#     (including a physical distribution medium), accompanied by the
#     Corresponding Source fixed on a durable physical medium
#     customarily used for software interchange.
# 
#     b) Convey the object code in, or embodied in, a physical product
#     (including a physical distribution medium), accompanied by a
#     written offer, valid for at least three years and valid for as
#     long as you offer spare parts or customer support for that product
#     model, to give anyone who possesses the object code either (1) a
#     copy of the Corresponding Source for all the software in the
#     product that is covered by this License, on a durable physical
#     medium customarily used for software interchange, for a price no
#     more than your reasonable cost of physically performing this
#     conveying of source, or (2) access to copy the
#     Corresponding Source from a network server at no charge.
# 
#     c) Convey individual copies of the object code with a copy of the
#     written offer to provide the Corresponding Source.  This
#     alternative is allowed only occasionally and noncommercially, and
#     only if you received the object code with such an offer, in accord
#     with subsection 6b.
# 
#     d) Convey the object code by offering access from a designated
#     place (gratis or for a charge), and offer equivalent access to the
#     Corresponding Source in the same way through the same place at no
#     further charge.  You need not require recipients to copy the
#     Corresponding Source along with the object code.  If the place to
#     copy the object code is a network server, the Corresponding Source
#     may be on a different server (operated by you or a third party)
#     that supports equivalent copying facilities, provided you maintain
#     clear directions next to the object code saying where to find the
#     Corresponding Source.  Regardless of what server hosts the
#     Corresponding Source, you remain obligated to ensure that it is
#     available for as long as needed to satisfy these requirements.
# 
#     e) Convey the object code using peer-to-peer transmission, provided
#     you inform other peers where the object code and Corresponding
#     Source of the work are being offered to the general public at no
#     charge under subsection 6d.
# 
#   A separable portion of the object code, whose source code is excluded
# from the Corresponding Source as a System Library, need not be
# included in conveying the object code work.
# 
#   A "User Product" is either (1) a "consumer product", which means any
# tangible personal property which is normally used for personal, family,
# or household purposes, or (2) anything designed or sold for incorporation
# into a dwelling.  In determining whether a product is a consumer product,
# doubtful cases shall be resolved in favor of coverage.  For a particular
# product received by a particular user, "normally used" refers to a
# typical or common use of that class of product, regardless of the status
# of the particular user or of the way in which the particular user
# actually uses, or expects or is expected to use, the product.  A product
# is a consumer product regardless of whether the product has substantial
# commercial, industrial or non-consumer uses, unless such uses represent
# the only significant mode of use of the product.
# 
#   "Installation Information" for a User Product means any methods,
# procedures, authorization keys, or other information required to install
# and execute modified versions of a covered work in that User Product from
# a modified version of its Corresponding Source.  The information must
# suffice to ensure that the continued functioning of the modified object
# code is in no case prevented or interfered with solely because
# modification has been made.
# 
#   If you convey an object code work under this section in, or with, or
# specifically for use in, a User Product, and the conveying occurs as
# part of a transaction in which the right of possession and use of the
# User Product is transferred to the recipient in perpetuity or for a
# fixed term (regardless of how the transaction is characterized), the
# Corresponding Source conveyed under this section must be accompanied
# by the Installation Information.  But this requirement does not apply
# if neither you nor any third party retains the ability to install
# modified object code on the User Product (for example, the work has
# been installed in ROM).
# 
#   The requirement to provide Installation Information does not include a
# requirement to continue to provide support service, warranty, or updates
# for a work that has been modified or installed by the recipient, or for
# the User Product in which it has been modified or installed.  Access to a
# network may be denied when the modification itself materially and
# adversely affects the operation of the network or violates the rules and
# protocols for communication across the network.
# 
#   Corresponding Source conveyed, and Installation Information provided,
# in accord with this section must be in a format that is publicly
# documented (and with an implementation available to the public in
# source code form), and must require no special password or key for
# unpacking, reading or copying.
# 
#   7. Additional Terms.
# 
#   "Additional permissions" are terms that supplement the terms of this
# License by making exceptions from one or more of its conditions.
# Additional permissions that are applicable to the entire Program shall
# be treated as though they were included in this License, to the extent
# that they are valid under applicable law.  If additional permissions
# apply only to part of the Program, that part may be used separately
# under those permissions, but the entire Program remains governed by
# this License without regard to the additional permissions.
# 
#   When you convey a copy of a covered work, you may at your option
# remove any additional permissions from that copy, or from any part of
# it.  (Additional permissions may be written to require their own
# removal in certain cases when you modify the work.)  You may place
# additional permissions on material, added by you to a covered work,
# for which you have or can give appropriate copyright permission.
# 
#   Notwithstanding any other provision of this License, for material you
# add to a covered work, you may (if authorized by the copyright holders of
# that material) supplement the terms of this License with terms:
# 
#     a) Disclaiming warranty or limiting liability differently from the
#     terms of sections 15 and 16 of this License; or
# 
#     b) Requiring preservation of specified reasonable legal notices or
#     author attributions in that material or in the Appropriate Legal
#     Notices displayed by works containing it; or
# 
#     c) Prohibiting misrepresentation of the origin of that material, or
#     requiring that modified versions of such material be marked in
#     reasonable ways as different from the original version; or
# 
#     d) Limiting the use for publicity purposes of names of licensors or
#     authors of the material; or
# 
#     e) Declining to grant rights under trademark law for use of some
#     trade names, trademarks, or service marks; or
# 
#     f) Requiring indemnification of licensors and authors of that
#     material by anyone who conveys the material (or modified versions of
#     it) with contractual assumptions of liability to the recipient, for
#     any liability that these contractual assumptions directly impose on
#     those licensors and authors.
# 
#   All other non-permissive additional terms are considered "further
# restrictions" within the meaning of section 10.  If the Program as you
# received it, or any part of it, contains a notice stating that it is
# governed by this License along with a term that is a further
# restriction, you may remove that term.  If a license document contains
# a further restriction but permits relicensing or conveying under this
# License, you may add to a covered work material governed by the terms
# of that license document, provided that the further restriction does
# not survive such relicensing or conveying.
# 
#   If you add terms to a covered work in accord with this section, you
# must place, in the relevant source files, a statement of the
# additional terms that apply to those files, or a notice indicating
# where to find the applicable terms.
# 
#   Additional terms, permissive or non-permissive, may be stated in the
# form of a separately written license, or stated as exceptions;
# the above requirements apply either way.
# 
#   8. Termination.
# 
#   You may not propagate or modify a covered work except as expressly
# provided under this License.  Any attempt otherwise to propagate or
# modify it is void, and will automatically terminate your rights under
# this License (including any patent licenses granted under the third
# paragraph of section 11).
# 
#   However, if you cease all violation of this License, then your
# license from a particular copyright holder is reinstated (a)
# provisionally, unless and until the copyright holder explicitly and
# finally terminates your license, and (b) permanently, if the copyright
# holder fails to notify you of the violation by some reasonable means
# prior to 60 days after the cessation.
# 
#   Moreover, your license from a particular copyright holder is
# reinstated permanently if the copyright holder notifies you of the
# violation by some reasonable means, this is the first time you have
# received notice of violation of this License (for any work) from that
# copyright holder, and you cure the violation prior to 30 days after
# your receipt of the notice.
# 
#   Termination of your rights under this section does not terminate the
# licenses of parties who have received copies or rights from you under
# this License.  If your rights have been terminated and not permanently
# reinstated, you do not qualify to receive new licenses for the same
# material under section 10.
# 
#   9. Acceptance Not Required for Having Copies.
# 
#   You are not required to accept this License in order to receive or
# run a copy of the Program.  Ancillary propagation of a covered work
# occurring solely as a consequence of using peer-to-peer transmission
# to receive a copy likewise does not require acceptance.  However,
# nothing other than this License grants you permission to propagate or
# modify any covered work.  These actions infringe copyright if you do
# not accept this License.  Therefore, by modifying or propagating a
# covered work, you indicate your acceptance of this License to do so.
# 
#   10. Automatic Licensing of Downstream Recipients.
# 
#   Each time you convey a covered work, the recipient automatically
# receives a license from the original licensors, to run, modify and
# propagate that work, subject to this License.  You are not responsible
# for enforcing compliance by third parties with this License.
# 
#   An "entity transaction" is a transaction transferring control of an
# organization, or substantially all assets of one, or subdividing an
# organization, or merging organizations.  If propagation of a covered
# work results from an entity transaction, each party to that
# transaction who receives a copy of the work also receives whatever
# licenses to the work the party's predecessor in interest had or could
# give under the previous paragraph, plus a right to possession of the
# Corresponding Source of the work from the predecessor in interest, if
# the predecessor has it or can get it with reasonable efforts.
# 
#   You may not impose any further restrictions on the exercise of the
# rights granted or affirmed under this License.  For example, you may
# not impose a license fee, royalty, or other charge for exercise of
# rights granted under this License, and you may not initiate litigation
# (including a cross-claim or counterclaim in a lawsuit) alleging that
# any patent claim is infringed by making, using, selling, offering for
# sale, or importing the Program or any portion of it.
# 
#   11. Patents.
# 
#   A "contributor" is a copyright holder who authorizes use under this
# License of the Program or a work on which the Program is based.  The
# work thus licensed is called the contributor's "contributor version".
# 
#   A contributor's "essential patent claims" are all patent claims
# owned or controlled by the contributor, whether already acquired or
# hereafter acquired, that would be infringed by some manner, permitted
# by this License, of making, using, or selling its contributor version,
# but do not include claims that would be infringed only as a
# consequence of further modification of the contributor version.  For
# purposes of this definition, "control" includes the right to grant
# patent sublicenses in a manner consistent with the requirements of
# this License.
# 
#   Each contributor grants you a non-exclusive, worldwide, royalty-free
# patent license under the contributor's essential patent claims, to
# make, use, sell, offer for sale, import and otherwise run, modify and
# propagate the contents of its contributor version.
# 
#   In the following three paragraphs, a "patent license" is any express
# agreement or commitment, however denominated, not to enforce a patent
# (such as an express permission to practice a patent or covenant not to
# sue for patent infringement).  To "grant" such a patent license to a
# party means to make such an agreement or commitment not to enforce a
# patent against the party.
# 
#   If you convey a covered work, knowingly relying on a patent license,
# and the Corresponding Source of the work is not available for anyone
# to copy, free of charge and under the terms of this License, through a
# publicly available network server or other readily accessible means,
# then you must either (1) cause the Corresponding Source to be so
# available, or (2) arrange to deprive yourself of the benefit of the
# patent license for this particular work, or (3) arrange, in a manner
# consistent with the requirements of this License, to extend the patent
# license to downstream recipients.  "Knowingly relying" means you have
# actual knowledge that, but for the patent license, your conveying the
# covered work in a country, or your recipient's use of the covered work
# in a country, would infringe one or more identifiable patents in that
# country that you have reason to believe are valid.
# 
#   If, pursuant to or in connection with a single transaction or
# arrangement, you convey, or propagate by procuring conveyance of, a
# covered work, and grant a patent license to some of the parties
# receiving the covered work authorizing them to use, propagate, modify
# or convey a specific copy of the covered work, then the patent license
# you grant is automatically extended to all recipients of the covered
# work and works based on it.
# 
#   A patent license is "discriminatory" if it does not include within
# the scope of its coverage, prohibits the exercise of, or is
# conditioned on the non-exercise of one or more of the rights that are
# specifically granted under this License.  You may not convey a covered
# work if you are a party to an arrangement with a third party that is
# in the business of distributing software, under which you make payment
# to the third party based on the extent of your activity of conveying
# the work, and under which the third party grants, to any of the
# parties who would receive the covered work from you, a discriminatory
# patent license (a) in connection with copies of the covered work
# conveyed by you (or copies made from those copies), or (b) primarily
# for and in connection with specific products or compilations that
# contain the covered work, unless you entered into that arrangement,
# or that patent license was granted, prior to 28 March 2007.
# 
#   Nothing in this License shall be construed as excluding or limiting
# any implied license or other defenses to infringement that may
# otherwise be available to you under applicable patent law.
# 
#   12. No Surrender of Others' Freedom.
# 
#   If conditions are imposed on you (whether by court order, agreement or
# otherwise) that contradict the conditions of this License, they do not
# excuse you from the conditions of this License.  If you cannot convey a
# covered work so as to satisfy simultaneously your obligations under this
# License and any other pertinent obligations, then as a consequence you may
# not convey it at all.  For example, if you agree to terms that obligate you
# to collect a royalty for further conveying from those to whom you convey
# the Program, the only way you could satisfy both those terms and this
# License would be to refrain entirely from conveying the Program.
# 
#   13. Use with the GNU Affero General Public License.
# 
#   Notwithstanding any other provision of this License, you have
# permission to link or combine any covered work with a work licensed
# under version 3 of the GNU Affero General Public License into a single
# combined work, and to convey the resulting work.  The terms of this
# License will continue to apply to the part which is the covered work,
# but the special requirements of the GNU Affero General Public License,
# section 13, concerning interaction through a network will apply to the
# combination as such.
# 
#   14. Revised Versions of this License.
# 
#   The Free Software Foundation may publish revised and/or new versions of
# the GNU General Public License from time to time.  Such new versions will
# be similar in spirit to the present version, but may differ in detail to
# address new problems or concerns.
# 
#   Each version is given a distinguishing version number.  If the
# Program specifies that a certain numbered version of the GNU General
# Public License "or any later version" applies to it, you have the
# option of following the terms and conditions either of that numbered
# version or of any later version published by the Free Software
# Foundation.  If the Program does not specify a version number of the
# GNU General Public License, you may choose any version ever published
# by the Free Software Foundation.
# 
#   If the Program specifies that a proxy can decide which future
# versions of the GNU General Public License can be used, that proxy's
# public statement of acceptance of a version permanently authorizes you
# to choose that version for the Program.
# 
#   Later license versions may give you additional or different
# permissions.  However, no additional obligations are imposed on any
# author or copyright holder as a result of your choosing to follow a
# later version.
# 
#   15. Disclaimer of Warranty.
# 
#   THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
# APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
# HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
# OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
# IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
# ALL NECESSARY SERVICING, REPAIR OR CORRECTION.
# 
#   16. Limitation of Liability.
# 
#   IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
# WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
# THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
# GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
# USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
# DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
# PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
# EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGES.
# 
#   17. Interpretation of Sections 15 and 16.
# 
#   If the disclaimer of warranty and limitation of liability provided
# above cannot be given local legal effect according to their terms,
# reviewing courts shall apply local law that most closely approximates
# an absolute waiver of all civil liability in connection with the
# Program, unless a warranty or assumption of liability accompanies a
# copy of the Program in return for a fee.
# 
#                      END OF TERMS AND CONDITIONS
# 
#             How to Apply These Terms to Your New Programs
# 
#   If you develop a new program, and you want it to be of the greatest
# possible use to the public, the best way to achieve this is to make it
# free software which everyone can redistribute and change under these terms.
# 
#   To do so, attach the following notices to the program.  It is safest
# to attach them to the start of each source file to most effectively
# state the exclusion of warranty; and each file should have at least
# the "copyright" line and a pointer to where the full notice is found.
# 
#     <one line to give the program's name and a brief idea of what it does.>
#     Copyright (C) <year>  <name of author>
# 
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
# Also add information on how to contact you by electronic and paper mail.
# 
#   If the program does terminal interaction, make it output a short
# notice like this when it starts in an interactive mode:
# 
#     <program>  Copyright (C) <year>  <name of author>
#     This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
#     This is free software, and you are welcome to redistribute it
#     under certain conditions; type `show c' for details.
# 
# The hypothetical commands `show w' and `show c' should show the appropriate
# parts of the General Public License.  Of course, your program's commands
# might be different; for a GUI interface, you would use an "about box".
# 
#   You should also get your employer (if you work as a programmer) or school,
# if any, to sign a "copyright disclaimer" for the program, if necessary.
# For more information on this, and how to apply and follow the GNU GPL, see
# <http://www.gnu.org/licenses/>.
# 
#   The GNU General Public License does not permit incorporating your program
# into proprietary programs.  If your program is a subroutine library, you
# may consider it more useful to permit linking proprietary applications with
# the library.  If this is what you want to do, use the GNU Lesser General
# Public License instead of this License.  But first, please read
# <http://www.gnu.org/philosophy/why-not-lgpl.html>.
# 
__NUMLOCK_PAYLOAD__
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
L3Vzci9saWIvbGlib2JqYy5BLmR5bGliAAAAAAAAAAAMAAAAOAAAABgAAAACAAAAAAABBQAAAQAv
dXNyL2xpYi9saWJTeXN0ZW0uQi5keWxpYgAAAAAAAAwAAABoAAAAGAAAAAIAAAAAfokGAACWAC9T
eXN0ZW0vTGlicmFyeS9GcmFtZXdvcmtzL0NvcmVGb3VuZGF0aW9uLmZyYW1ld29yay9WZXJzaW9u
cy9BL0NvcmVGb3VuZGF0aW9uAAAADAAAAGgAAAAYAAAAAgAAAAQMRAUAAEAAL1N5c3RlbS9MaWJy
YXJ5L0ZyYW1ld29ya3MvQ29yZUdyYXBoaWNzLmZyYW1ld29yay9WZXJzaW9ucy9BL0NvcmVHcmFw
aGljcwAAAAAAAAAMAAAAWAAAABgAAAACAAAAAAATAQAAAQAvU3lzdGVtL0xpYnJhcnkvRnJhbWV3
b3Jrcy9JT0tpdC5mcmFtZXdvcmsvVmVyc2lvbnMvQS9JT0tpdAAAAAAAJgAAABAAAABINgAAEAAA
ACkAAAAQAAAAWDYAAAAAAAAdAAAAEAAAAKBEAABgSQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFVIieVIg+wgx0X8AAAAAIl9+EiJdfBIjT3n
DgAAsADoBA0AAIt9+EiLdfCJRezoHQAAAEiNPRoPAACwAOjnDAAAMcmJReiJyEiDxCBdw2aQVUiJ
5UiD7EBIiwXZEgAASIsASIlF+Il93EiJddCDfdwBD4UPAAAA6EQDAAC/AQAAAOh4DAAAxkXPAMZF
zgBIiwVLDgAASIlF4EiLBUgOAABIiUXox0XIAQAAAItFyDtF3A+NyAIAAEiLRdBIY03ISIs8yEiN
NYwOAADoXwwAAIP4AA+FCQAAAMZFzgHpiwIAAEiLRdBIY03ISIs8yEiNNWoOAADoNQwAAIP4AA+F
DAAAAMYFFxQAAAHpWQIAAEiLRdBIY03ISIs8yEiNNUAOAADoCAwAAIP4AA+FCQAAAMZFzwHpKgIA
AEiLRdBIY03ISIs8yEiNNRwOAADo3gsAAIP4AA+FDAAAAMdF5AEAAADp+AEAAEiLRdBIY03ISIs8
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
icroNQAAAEiLRdhIicfoOwAAAOkAAAAASItF8EiJRfhIi0X4SIPEMF3D/yUgBwAA/yUiBwAA/yUk
BwAA/yUmBwAA/yUoBwAA/yUqBwAA/yUsBwAA/yUuBwAA/yUwBwAA/yUyBwAA/yU0BwAA/yU2BwAA
/yU4BwAA/yU6BwAA/yU8BwAA/yU+BwAA/yVABwAA/yVCBwAA/yVEBwAA/yVGBwAA/yVIBwAA/yVK
BwAA/yVMBwAA/yVOBwAA/yVQBwAA/yVSBwAA/yVUBwAA/yVWBwAA/yVYBwAA/yVaBwAA/yVcBwAA
/yVeBwAA/yVgBwAA/yViBwAA/yVkBwAA/yVmBwAA/yVoBwAA/yVqBwAA/yVsBwAATI0d9QUAAEFT
/yUlBgAAkGisAwAA6eb///9ozAMAAOnc////aEoDAADp0v///2hjAwAA6cj///9ocAMAAOm+////
aIADAADptP///2iQAwAA6ar///9onQMAAOmg////aO0DAADplv///2j8AwAA6Yz///9oAAAAAOmC
////aBcAAADpeP///2g1AAAA6W7///9oVgAAAOlk////aHIAAADpWv///2iXAAAA6VD///9orQAA
AOlG////aL4AAADpPP///2jYAAAA6TL///9o9AAAAOko////aAkBAADpHv///2gfAQAA6RT///9o
NgEAAOkK////aKoBAADpAP///2jIAQAA6fb+//9o8AEAAOns/v//aA8CAADp4v7//2grAgAA6dj+
//9oRwIAAOnO/v//aGQCAADpxP7//2iFAgAA6br+//9opQIAAOmw/v//aMACAADppv7//2jZAgAA
6Zz+//9o/wIAAOmS/v//aCgDAADpiP7//2hUAQAA6X7+//9oeAEAAOl0/v//aJEBAADpav7//wAA
AAAAAAMAAAAAAAAAAAAAAAAAAAD/////////////////////bnVtAGNhcHMAc2Nyb2xsAC0AKwBT
ZXRMRURzIHZlcnNpb24gMC4yICsgTW9uaXRvciAtIEJhc2VkIG9uIGh0dHBzOi8vZ2l0aHViLmNv
bS9kYW1pZW5nL3NldGxlZHNtYWMKAAoAbW9uaXRvcgAtdgAtbmFtZQArbnVtAC1udW0AXm51bQAr
Y2FwcwAtY2FwcwBeY2FwcwArc2Nyb2xsAC1zY3JvbGwAXnNjcm9sbABVbmtub3duIG9wdGlvbiAl
cwoKAFN0YXJ0aW5nIGluIG1vbml0b3IgbW9kZS4KAEVSUk9SOiBmYWlsZWQgdG8gY3JlYXRlIGV2
ZW50IHRhcAoAQ2VhdGVkIGV2ZW50IHRhcC4KAEV2ZW50IHRhYiBlbmFibGVkLCBzdGFydGluZyBt
b25pdG9yLgoARXZlbnQgdGFwIHRpbWVkIG91dDogcmVzdGFydGluZyB0YXAAVXNhZ2U6CXNldGxl
ZHMgW21vbml0b3JdIFstdl0gWy1uYW1lIHdpbGRjYXJkXSBbWyt8LXxeXVsgbnVtIHwgY2FwcyB8
IHNjcm9sbF1dClRodXMsCXNldGxlZHMgK2NhcHMgLW51bSBec2Nyb2xsCndpbGwgc2V0IENhcHNM
b2NrLCBjbGVhciBOdW1Mb2NrIGFuZCB0b2dnbGUgU2Nyb2xsTG9jay4KQW55IGxlZHMgY2hhbmdl
ZCBhcmUgcmVwb3J0ZWQgZm9yIGVhY2gga2V5Ym9hcmQuClNwZWNpZnkgLXYgdG8gc2hvd3Mgc3Rh
dGUgb2YgYWxsIGxlZHMuClNwZWNpZnkgLW5hbWUgdG8gbWF0Y2gga2V5Ym9hcmQgbmFtZSB3aXRo
IGEgd2lsZGNhcmQKVXNlIHRoZSAibW9uaXRvciIgc3ViIGNvbW1hbmQgdG8gcnVuIGNvbnRpbm91
c2x5IGFuZCB0b2dnbGUgTEVEcyBvbiBrZXlwcmVzcy4AUHJvZHVjdABEZXZpY2U6ICVzICVzJXMg
AApTb21lIHN0YXRlIGNvdWxkIG5vdCBiZSBkZXRlcm1pbmVkLiBQbGVhc2UgdHJ5IHJ1bm5pbmcg
YXMgcm9vdC9zdWRvLgoARVJST1I6IEZhaWxlZCB0byBjcmVhdGUgSU9ISUQgbWFuYWdlci4KAEVS
Uk9SOiBGYWlsZWQgdG8gZ2V0IGRpY3Rpb25hcnkgdXNhZ2UgcGFnZSBmb3Iga0hJRFVzYWdlX0dE
X0tleWJvYXJkLgoARVJST1I6IENvdWxkIG5vdCBmaW5kIGFueSBrZXlib2FyZCBkZXZpY2VzLgoA
RGV2aWNlVXNhZ2UAAAABAAAAHAAAAAAAAAAcAAAAAAAAABwAAAACAAAA0AwAADQAAAA0AAAAGxkA
AAAAAAA0AAAAAwAAAAwAAQAQAAEAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAeBoAAAEAAACC
GgAAAQAAAIwaAAABAAAAlhoAAAEAAACgGgAAAQAAAKoaAAABAAAAtBoAAAEAAAC+GgAAAQAAAMga
AAABAAAA0hoAAAEAAADcGgAAAQAAAOYaAAABAAAA8BoAAAEAAAB8GwAAAQAAAIYbAAABAAAAkBsA
AAEAAAD6GgAAAQAAAAQbAAABAAAADhsAAAEAAAAYGwAAAQAAACIbAAABAAAALBsAAAEAAAA2GwAA
AQAAAEAbAAABAAAAShsAAAEAAABUGwAAAQAAAF4bAAABAAAAaBsAAAEAAAByGwAAAQAAACgaAAAB
AAAAMhoAAAEAAAA8GgAAAQAAAEYaAAABAAAAUBoAAAEAAABaGgAAAQAAABQaAAABAAAAHhoAAAEA
AABkGgAAAQAAAG4aAAABAAAAAAAAAAAAAADIBwAAAAAAAKIeAAABAAAABwAAAAAAAAAAAAAAAAAA
AMgHAAAAAAAAnh8AAAEAAAALAAAAAAAAAAAAAABAAAAAwBsAAAEAAADEGwAAAQAAAMkbAAABAAAA
AAAAAAAAAADQGwAAAQAAANIbAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAESJAYCdCcBhwEFNBUgAAABNAX19fc3Rh
Y2tfY2hrX2d1YXJkAFFyCJBAX19fc3RkZXJycACQQGR5bGRfc3R1Yl9iaW5kZXIAgCCQFEBfX19D
RkNvbnN0YW50U3RyaW5nQ2xhc3NSZWZlcmVuY2UAgLgCs5BAX2tDRkFsbG9jYXRvckRlZmF1bHQA
gPj8/////////wGQQF9rQ0ZSdW5Mb29wQ29tbW9uTW9kZXMAkEBfa0NGVHlwZURpY3Rpb25hcnlL
ZXlDYWxsQmFja3MAkEBfa0NGVHlwZURpY3Rpb25hcnlWYWx1ZUNhbGxCYWNrcwCQAAAAAAByQBRA
X0NGQXJyYXlHZXRDb3VudACQAHJIFEBfQ0ZBcnJheUdldFZhbHVlQXRJbmRleACQAHJQFEBfQ0ZE
aWN0aW9uYXJ5Q3JlYXRlTXV0YWJsZQCQAHJYFEBfQ0ZEaWN0aW9uYXJ5U2V0VmFsdWUAkAByYBRA
X0NGTWFjaFBvcnRDcmVhdGVSdW5Mb29wU291cmNlAJAAcmgUQF9DRk51bWJlckNyZWF0ZQCQAHJw
FEBfQ0ZSZWxlYXNlAJAAcngUQF9DRlJ1bkxvb3BBZGRTb3VyY2UAkABygAEUQF9DRlJ1bkxvb3BH
ZXRDdXJyZW50AJAAcogBFEBfQ0ZSdW5Mb29wUnVuAJAAcpABFEBfQ0ZTZXRHZXRDb3VudACQAHKY
ARRAX0NGU2V0R2V0VmFsdWVzAJAAcqABFEBfQ0ZTdHJpbmdHZXRDU3RyaW5nUHRyAJAAcqgBFUBf
Q0dFdmVudEdldEludGVnZXJWYWx1ZUZpZWxkAJAAcrABFUBfQ0dFdmVudFRhcENyZWF0ZQCQAHK4
ARVAX0NHRXZlbnRUYXBFbmFibGUAkABywAEWQF9JT0hJRERldmljZUNvbmZvcm1zVG8AkAByyAEW
QF9JT0hJRERldmljZUNvcHlNYXRjaGluZ0VsZW1lbnRzAJAActABFkBfSU9ISUREZXZpY2VHZXRQ
cm9wZXJ0eQCQAHLYARZAX0lPSElERGV2aWNlR2V0VmFsdWUAkABy4AEWQF9JT0hJRERldmljZVNl
dFZhbHVlAJAAcugBFkBfSU9ISURFbGVtZW50R2V0VXNhZ2UAkABy8AEWQF9JT0hJREVsZW1lbnRH
ZXRVc2FnZVBhZ2UAkABy+AEWQF9JT0hJRE1hbmFnZXJDb3B5RGV2aWNlcwCQAHKAAhZAX0lPSElE
TWFuYWdlckNyZWF0ZQCQAHKIAhZAX0lPSElETWFuYWdlck9wZW4AkABykAIWQF9JT0hJRE1hbmFn
ZXJTZXREZXZpY2VNYXRjaGluZwCQAHKYAhZAX0lPSElEVmFsdWVDcmVhdGVXaXRoSW50ZWdlclZh
bHVlAJAAcqACFkBfSU9ISURWYWx1ZUdldEludGVnZXJWYWx1ZQCQAHKoAhNAX19fc3RhY2tfY2hr
X2ZhaWwAkABysAITQF9leGl0AJAAcrgCE0BfZm5tYXRjaACQAHLAAhNAX2ZwcmludGYAkAByyAIT
QF9mcmVlAJAActACE0BfbWFsbG9jAJAActgCEkBfb2JqY19hdXRvcmVsZWFzZVBvb2xQb3AAkABy
4AISQF9vYmpjX2F1dG9yZWxlYXNlUG9vbFB1c2gAkABy6AITQF9wcmludGYAkABy8AITQF9zdHJj
YXNlY21wAJAAAAABXwAFAApfbWhfZXhlY3V0ZV9oZWFkZXIAhAFtYQCIAXBhcnNlT3B0aW9ucwCc
AWUAoQFzAMUBaXNLZXlib2FyZERldmljZQCVAmdldEtleWJvYXJkRGljdGlvbmFyeQCfAmxlZE5h
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
AAAAAAAAAADcAwAAAQAABAAAAAAAAAAA8wMAAAEAAAQAAAAAAAAAABIEAAABAAAEAAAAAAAAAAAz
BAAAAQAAAwAAAAAAAAAAOwQAAAEAAAIAAAAAAAAAAFQEAAABAAACAAAAAAAAAABuBAAAAQAAAwAA
AAAAAAAAdgQAAAEAAAMAAAAAAAAAAIIEAAABAAADAAAAAAAAAAA+AAAAPwAAAEAAAABBAAAAQgAA
AEMAAABEAAAARQAAAEYAAABHAAAASAAAAEkAAABKAAAASwAAAEwAAABNAAAATgAAAE8AAABQAAAA
UQAAAFIAAABTAAAAVAAAAFUAAABWAAAAVwAAAFgAAABZAAAAWgAAAFwAAABfAAAAYAAAAGEAAABi
AAAAZwAAAGgAAABpAAAAagAAAGsAAAAAAABAXQAAAF4AAABjAAAAZAAAAGUAAABmAAAAbAAAAD4A
AAA/AAAAQAAAAEEAAABCAAAAQwAAAEQAAABFAAAARgAAAEcAAABIAAAASQAAAEoAAABLAAAATAAA
AE0AAABOAAAATwAAAFAAAABRAAAAUgAAAFMAAABUAAAAVQAAAFYAAABXAAAAWAAAAFkAAABaAAAA
XAAAAF8AAABgAAAAYQAAAGIAAABnAAAAaAAAAGkAAABqAAAAawAAACAAX19taF9leGVjdXRlX2hl
YWRlcgBfZXZlbnRDYWxsYmFjawBfZXhwbGFpblVzYWdlAF9nZXRLZXlib2FyZERpY3Rpb25hcnkA
X2lzS2V5Ym9hcmREZXZpY2UAX2xlZE5hbWVzAF9tYWluAF9tYXhMZWRzAF9uYW1lTWF0Y2gAX3Bh
cnNlT3B0aW9ucwBfc2V0QWxsS2V5Ym9hcmRzAF9zZXRLZXlib2FyZABfc3RhcnRNb25pdG9yAF9z
dGF0ZVN5bWJvbABfdmVyYm9zZQBfQ0ZBcnJheUdldENvdW50AF9DRkFycmF5R2V0VmFsdWVBdElu
ZGV4AF9DRkRpY3Rpb25hcnlDcmVhdGVNdXRhYmxlAF9DRkRpY3Rpb25hcnlTZXRWYWx1ZQBfQ0ZN
YWNoUG9ydENyZWF0ZVJ1bkxvb3BTb3VyY2UAX0NGTnVtYmVyQ3JlYXRlAF9DRlJlbGVhc2UAX0NG
UnVuTG9vcEFkZFNvdXJjZQBfQ0ZSdW5Mb29wR2V0Q3VycmVudABfQ0ZSdW5Mb29wUnVuAF9DRlNl
dEdldENvdW50AF9DRlNldEdldFZhbHVlcwBfQ0ZTdHJpbmdHZXRDU3RyaW5nUHRyAF9DR0V2ZW50
R2V0SW50ZWdlclZhbHVlRmllbGQAX0NHRXZlbnRUYXBDcmVhdGUAX0NHRXZlbnRUYXBFbmFibGUA
X0lPSElERGV2aWNlQ29uZm9ybXNUbwBfSU9ISUREZXZpY2VDb3B5TWF0Y2hpbmdFbGVtZW50cwBf
SU9ISUREZXZpY2VHZXRQcm9wZXJ0eQBfSU9ISUREZXZpY2VHZXRWYWx1ZQBfSU9ISUREZXZpY2VT
ZXRWYWx1ZQBfSU9ISURFbGVtZW50R2V0VXNhZ2UAX0lPSElERWxlbWVudEdldFVzYWdlUGFnZQBf
SU9ISURNYW5hZ2VyQ29weURldmljZXMAX0lPSElETWFuYWdlckNyZWF0ZQBfSU9ISURNYW5hZ2Vy
T3BlbgBfSU9ISURNYW5hZ2VyU2V0RGV2aWNlTWF0Y2hpbmcAX0lPSElEVmFsdWVDcmVhdGVXaXRo
SW50ZWdlclZhbHVlAF9JT0hJRFZhbHVlR2V0SW50ZWdlclZhbHVlAF9fX0NGQ29uc3RhbnRTdHJp
bmdDbGFzc1JlZmVyZW5jZQBfX19zdGFja19jaGtfZmFpbABfX19zdGFja19jaGtfZ3VhcmQAX19f
c3RkZXJycABfZXhpdABfZm5tYXRjaABfZnByaW50ZgBfZnJlZQBfa0NGQWxsb2NhdG9yRGVmYXVs
dABfa0NGUnVuTG9vcENvbW1vbk1vZGVzAF9rQ0ZUeXBlRGljdGlvbmFyeUtleUNhbGxCYWNrcwBf
a0NGVHlwZURpY3Rpb25hcnlWYWx1ZUNhbGxCYWNrcwBfbWFsbG9jAF9vYmpjX2F1dG9yZWxlYXNl
UG9vbFBvcABfb2JqY19hdXRvcmVsZWFzZVBvb2xQdXNoAF9wcmludGYAX3N0cmNhc2VjbXAAZHls
ZF9zdHViX2JpbmRlcgAvVXNlcnMveGlhb20vRGVza3RvcC9zZXRsZWRzbWFjLW1hc3Rlci9Tb3Vy
Y2UvU2V0TGVkcy8AbWFpbi5tAC9Vc2Vycy94aWFvbS9EZXNrdG9wL3NldGxlZHNtYWMtbWFzdGVy
L1NvdXJjZS9idWlsZC9TZXRMRURzLmJ1aWxkL0RlYnVnL1NldExlZHMuYnVpbGQvT2JqZWN0cy1u
b3JtYWwveDg2XzY0L21haW4ubwBfbWFpbgBfcGFyc2VPcHRpb25zAF9leHBsYWluVXNhZ2UAX3N0
YXJ0TW9uaXRvcgBfc2V0QWxsS2V5Ym9hcmRzAF9ldmVudENhbGxiYWNrAF9pc0tleWJvYXJkRGV2
aWNlAF9zZXRLZXlib2FyZABfZ2V0S2V5Ym9hcmREaWN0aW9uYXJ5AF9tYXhMZWRzAF9sZWROYW1l
cwBfc3RhdGVTeW1ib2wAX3ZlcmJvc2UAX25hbWVNYXRjaABfZXZlbnRUYXAAX2V2ZW50VGFwAAAA
AAAAAAAAAAAAAAAA+t4MwAAAAtwAAAAEAAAAAAAAACwAAAACAAABzQAAAAUAAAHZAAEAAAAAAtT6
3gwCAAABoQACAQAAAAACAAABAQAAADAAAAAFAAAABQAARKAgAgAMAAAAAAAAAABTZXRMZWRzLTU1
NTU0OTQ0NTk2ZTk5ZDBjZjYzM2NiNGE4NWRiODU1NjVkZWJiZjkAO6KkQEoplDyxE3wYsjpNEd1t
L5EpxlOuFuaVpSiZYeYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAmHkgkE6rZQ51eIwFSqCwUk5qgL/HGqMt+NI3phdD+YYAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPT3PDQRZRIA8GPMf/TwBVXmXYCeFiC8F+rq0SMo
etAMlrJwV79+pKnV4rfMH+fgjKUddztPzP95gCd9UK6kSlv0jUw5DC3qfJgNLl80cVuzCrIhGwMJ
PuyYowUTXmrnYBVPMtit5/kJtHK20Pow+OxrsUdyb/CgddMf+F8Mnlannoa1CR0i4ULaHa2y1GH8
aEVdJ/57zu2TXD9SFDB5XTT63gwBAAAADAAAAAD63nFxAAAA+zw/eG1sIHZlcnNpb249IjEuMCIg
ZW5jb2Rpbmc9IlVURi04Ij8+CjwhRE9DVFlQRSBwbGlzdCBQVUJMSUMgIi0vL0FwcGxlLy9EVEQg
UExJU1QgMS4wLy9FTiIgImh0dHA6Ly93d3cuYXBwbGUuY29tL0RURHMvUHJvcGVydHlMaXN0LTEu
MC5kdGQiPgo8cGxpc3QgdmVyc2lvbj0iMS4wIj4KPGRpY3Q+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1
cml0eS5nZXQtdGFzay1hbGxvdzwva2V5PgoJPHRydWUvPgo8L2RpY3Q+CjwvcGxpc3Q+CvreCwEA
AAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==
