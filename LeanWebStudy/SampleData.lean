import MapleSQL

namespace LeanWebStudy.SampleData

def sourceUrl : String :=
  "https://github.com/typicode/jsonplaceholder/blob/7ae4432ac3f60e7226a899c25e04826207d07098/data.json"

def licenseUrl : String :=
  "https://github.com/typicode/jsonplaceholder/blob/7ae4432ac3f60e7226a899c25e04826207d07098/LICENSE"

def generatorUrl : String :=
  "https://github.com/typicode/jsonplaceholder/blob/7ae4432ac3f60e7226a899c25e04826207d07098/seed.js"

def duplicateName : String := "Leanne Graham"

def dummyEmail (id : Nat) : String := s!"user-{id}@example.invalid"

-- Adapted from data.json; ID 2 shares ID 1's name. Emails are generated locally.
-- See data/LICENSE-jsonplaceholder.
def users : Array (Array MapleSQL.Value) := #[
  #[.integer 1, .text duplicateName, .text (dummyEmail 1)],
  #[.integer 2, .text duplicateName, .text (dummyEmail 2)],
  #[.integer 3, .text "Clementine Bauch", .text (dummyEmail 3)],
  #[.integer 4, .text "Patricia Lebsack", .text (dummyEmail 4)],
  #[.integer 5, .text "Chelsey Dietrich", .text (dummyEmail 5)],
  #[.integer 6, .text "Mrs. Dennis Schulist", .text (dummyEmail 6)],
  #[.integer 7, .text "Kurtis Weissnat", .text (dummyEmail 7)],
  #[.integer 8, .text "Nicholas Runolfsdottir V", .text (dummyEmail 8)],
  #[.integer 9, .text "Glenna Reichert", .text (dummyEmail 9)],
  #[.integer 10, .text "Clementina DuBuque", .text (dummyEmail 10)]]

def sourceSchema : String :=
  "{ users: [{\n" ++
  "  id: integer, name: string, username: string, email: string,\n" ++
  "  address: {\n" ++
  "    street: string, suite: string, city: string, zipcode: string,\n" ++
  "    geo: { lat: string, lng: string }\n" ++
  "  },\n" ++
  "  phone: string, website: string,\n" ++
  "  company: { name: string, catchPhrase: string, bs: string }\n" ++
  "}] }"

def sqliteSchema : String :=
  "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE)"

def insertStatement : MapleSQL.Statement :=
  .insert "users" #["id", "name", "email"] users

def emailsByNameStatement (name : String) : MapleSQL.Statement :=
  .select #[.named "email"] "users"
    (some (.equal (.column "name") (.parameter (.text name))))

end LeanWebStudy.SampleData
