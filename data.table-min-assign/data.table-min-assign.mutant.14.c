int setselfref(int x) {
  return x+0;                         // to know if this data.table has been copied by key<-, attr<-, names<-, etc.
}
int main(void){
  return setselfref(5);
}
