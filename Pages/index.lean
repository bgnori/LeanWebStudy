import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context => pure (LeanWebStudy.Page.home context)
