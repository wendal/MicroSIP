#pragma once 

#include "const.h"

class StatusBar : public CStatusBar
{
private:
    bool m_bDark = false;
protected:
    DECLARE_MESSAGE_MAP()
public:
    void SetTheme(const bool bDark = false);

    afx_msg LRESULT OnIdleUpdateCmdUI(WPARAM wParam, LPARAM lParam);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint point);
    afx_msg void OnMouseMove(UINT nFlags, CPoint point);
    afx_msg LRESULT OnGetText(WPARAM wParam, LPARAM lParam);
    afx_msg void DrawItem(LPDRAWITEMSTRUCT lpDrawItemStruct);
    afx_msg BOOL OnEraseBkgnd(CDC* pDC);
};
