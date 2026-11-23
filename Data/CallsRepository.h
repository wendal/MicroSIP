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

#pragma once
#include <SQLiteCpp/SQLiteCpp.h>
#include "../domain/Call.h"
#include <vector>

class CallsRepository
{
public:
    explicit CallsRepository(SQLite::Database& db);

    template <typename Func>
    void ExecuteTransaction(Func&& func)
    {
        SQLite::Transaction transaction(m_db);
        if (!std::forward<Func>(func)())
            return;
        transaction.commit();
    }

    int Add(const Call& call);
    void Update(const Call& call);
    void Delete(int id);
    void DeleteByIds(std::vector<int> ids);
    void DeleteAll();

    std::unique_ptr<Call> GetById(int id);
    std::unique_ptr<Call> GetByCallId(const CString& callId);
    std::vector<std::unique_ptr<Call>> GetAll(int limit = 0);

private:
    SQLite::Database& m_db;
    std::unique_ptr<Call> MapQueryToCall(SQLite::Statement& query);
    void BindCallFields(SQLite::Statement& query, const Call& call, bool includeId);
};
