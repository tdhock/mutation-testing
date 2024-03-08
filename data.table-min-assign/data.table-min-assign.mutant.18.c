int setselfref(int x) {
  return x+1;                         // to know if this data.table has been copied by key<-, names<-, attr<-, etc.
}
int main(void){
  return setselfref(5);
}
