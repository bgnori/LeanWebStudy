import LeanWebStudy.Page
import LeanWebStudy.Shop

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (LeanWebStudy.Shop.render context)
