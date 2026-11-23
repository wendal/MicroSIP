/*
 * Copyright (C) 2011-2026 MicroSIP (http://www.microsip.org)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "stdafx.h"
#include "StatusBar.h"   
#include "global.h"

static bool IsWritableMemory(const void* ptr, SIZE_T size)
{
    if (!ptr || size == 0)
        return false;

    MEMORY_BASIC_INFORMATION mbi = {};

    if (VirtualQuery(ptr, &mbi, sizeof(mbi)) != sizeof(mbi))
        return false;

    if (mbi.State != MEM_COMMIT)
        return false;

    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))
        return false;

    DWORD protect = mbi.Protect & 0xFF;

    if (protect != PAGE_READWRITE &&
        protect != PAGE_WRITECOPY &&
        protect != PAGE_EXECUTE_READWRITE &&
        protect != PAGE_EXECUTE_WRITECOPY)
        return false;

    BYTE* end = static_cast<BYTE*>(mbi.BaseAddress) + mbi.RegionSize;
    BYTE* requestedEnd = static_cast<BYTE*>(const_cast<void*>(ptr)) + size;

    return requestedEnd <= end;
}

BEGIN_MESSAGE_MAP(StatusBar, CStatusBar)
    //{{AFX_MSG_MAP(StatusBar)   
    ON_MESSAGE(WM_IDLEUPDATECMDUI, OnIdleUpdateCmdUI)
    ON_WM_LBUTTONUP()
    ON_WM_MOUSEMOVE()
    ON_MESSAGE(SB_GETTEXTW, OnGetText)
    ON_WM_ERASEBKGND()
    //}}AFX_MSG_MAP   
END_MESSAGE_MAP()

LRESULT StatusBar::OnIdleUpdateCmdUI(WPARAM wParam, LPARAM lParam)
{
    if (IsWindowVisible())
    {
        CFrameWnd* pParent = (CFrameWnd*)GetParent();
        if (pParent)
            OnUpdateCmdUI(pParent, (BOOL)wParam);
    }
    return 0L;
}

void StatusBar::OnLButtonUp(UINT nFlags, CPoint point)
{
}

void StatusBar::OnMouseMove(UINT nFlags, CPoint point)
{
}

LRESULT StatusBar::OnGetText(WPARAM wParam, LPARAM lParam)
{
    if (!lParam)
        return 0;

    // Get required text length.
    LRESULT textInfo = DefWindowProc(
        SB_GETTEXTLENGTH,
        wParam,
        0
    );

    // SBT_OWNERDRAW returns application-defined data, not text.
    if (HIWORD(textInfo) & SBT_OWNERDRAW)
        return 0;

    SIZE_T bufferSize = (static_cast<SIZE_T>(LOWORD(textInfo)) + 1)
        * sizeof(WCHAR);

    if (!IsWritableMemory(
        reinterpret_cast<void*>(lParam),
        bufferSize))
    {
        TRACE(_T("Invalid SB_GETTEXTW buffer: %p, size: %zu\n"),
            reinterpret_cast<void*>(lParam), bufferSize);

        return 0;
    }

    return DefWindowProc(SB_GETTEXTW, wParam, lParam);
}

BOOL StatusBar::OnEraseBkgnd(CDC* pDC)
{
    CRect rect;
    GetClientRect(&rect);

    pDC->FillSolidRect(rect, m_bDark ? RGB(32, 32, 32) : RGB(240, 240, 240));

    pDC->FillSolidRect(
        rect.left,
        rect.top,
        rect.Width(),
        1,
        RGB(215, 215, 215)
    );

    return TRUE;
}

void StatusBar::DrawItem(LPDRAWITEMSTRUCT lpDrawItemStruct)
{
    CDC dc;
    dc.Attach(lpDrawItemStruct->hDC);

    const int savedDC = dc.SaveDC();

    CRect rect(lpDrawItemStruct->rcItem);

    // DPI scaling
    UINT dpi = dc.GetDeviceCaps(LOGPIXELSX);

    auto Scale = [dpi](int value) -> int
        {
            return MulDiv(value, dpi, 96);
        };

    const int padding = Scale(4);
    const int iconSize = Scale(16);
    const int iconTextGap = Scale(4);

    // Background
    dc.FillSolidRect(rect, m_bDark ? RGB(32, 32, 32) : RGB(240, 240, 240));

    // Get icon from status bar
    HICON hIcon = GetStatusBarCtrl().GetIcon(
        lpDrawItemStruct->itemID);

    int x = rect.left + padding;

    if (hIcon)
    {
        int y = rect.top + (rect.Height() - iconSize) / 2;

        DrawIconEx(
            dc.GetSafeHdc(),
            x,
            y,
            hIcon,
            iconSize,
            iconSize,
            0,
            nullptr,
            DI_NORMAL
        );

        rect.left = x + iconSize + iconTextGap;
    }

    // Text
    CString text;
    GetPaneText(lpDrawItemStruct->itemID, text);

    dc.SetTextColor(m_bDark ? RGB(240, 240, 240) : RGB(32, 32, 32));
    dc.SetBkMode(TRANSPARENT);

    dc.DrawText(
        text,
        rect,
        DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS
    );

    dc.RestoreDC(savedDC);
    dc.Detach();
}

void StatusBar::SetTheme(const bool bDark)
{
    m_bDark = bDark;

    if (GetSafeHwnd())
        Invalidate();
}
